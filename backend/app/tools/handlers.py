"""Python implementations behind each tool the AI examiner can call.

Each handler takes (db, session, args) and returns a JSON-serializable dict
that gets fed back to the model as the tool result.
"""

import datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session as DBSession
from twilio.base.exceptions import TwilioException, TwilioRestException
from twilio.rest import Client

from ..config import settings
from ..models import AgentSession, ContactDevice, NotificationAttempt, TestResult
from ..notifications import apns_provider, safety_alert_message


def retrieve_baseline(db: DBSession, session: AgentSession, args: dict) -> dict:
    user = session.event.user
    baseline = user.baseline
    if baseline is None:
        return {"error": "no baseline on file for this user"}
    return {
        "reaction_time_ms": baseline.reaction_time_ms,
        "gyro_stability_score": baseline.gyro_stability_score,
        "memory_recall_score": baseline.memory_recall_score,
        "weight_kg": user.weight_kg,
        "height_cm": user.height_cm,
        "bmi": user.bmi,
    }


_BASELINE_FIELD_BY_TEST = {
    "reaction": "reaction_time_ms",
    "gyro": "gyro_stability_score",
    "balance": "gyro_stability_score",
    "memory": "memory_recall_score",
}


def analyze_deviation(db: DBSession, session: AgentSession, args: dict) -> dict:
    test_type = args["test_type"]
    baseline = session.event.user.baseline
    if baseline is None:
        return {"error": "no baseline on file for this user"}

    latest = (
        db.query(TestResult)
        .filter(TestResult.session_id == session.id, TestResult.test_type == test_type)
        .order_by(TestResult.created_at.desc())
        .first()
    )
    if latest is None:
        return {"error": f"no '{test_type}' result submitted yet this session"}

    baseline_value = getattr(baseline, _BASELINE_FIELD_BY_TEST[test_type])
    current_value = latest.raw_value
    percent_change = ((current_value - baseline_value) / baseline_value) * 100 if baseline_value else 0.0

    return {
        "test_type": test_type,
        "baseline_value": baseline_value,
        "current_value": current_value,
        "percent_change": round(percent_change, 1),
    }


def update_confidence(db: DBSession, session: AgentSession, args: dict) -> dict:
    session.confidence = args["confidence"]
    session.status = args["level"]
    log = list(session.reasoning_log or [])
    log.append(args["reasoning"])
    session.reasoning_log = log
    db.add(session)
    db.commit()
    return {"acknowledged": True, "confidence": session.confidence, "level": session.status}


def request_test(db: DBSession, session: AgentSession, args: dict) -> dict:
    session.pending_test = args["test_type"]
    db.add(session)
    db.commit()
    return {"acknowledged": True, "requested_test": args["test_type"], "reason": args.get("reason")}


_ACCEPTED_STATUSES = {"accepted", "queued", "sent", "delivered", "acknowledged"}
_IN_FLIGHT_STATUSES = {"pending", "sending"}


def _attempt_result(attempt: NotificationAttempt) -> dict:
    return {
        "attempt_id": attempt.id,
        "contact": attempt.contact.name,
        "channel": attempt.channel,
        "status": attempt.status,
        "provider_status": attempt.provider_status,
        "provider_message_id": attempt.provider_message_id,
        "error_code": attempt.error_code,
        "error_message": attempt.error_message,
        "provider_details": attempt.provider_details or [],
    }


def _attempt_is_stale(attempt: NotificationAttempt, now: datetime.datetime) -> bool:
    if attempt.status not in _IN_FLIGHT_STATUSES:
        return False
    deadline = attempt.lease_expires_at
    if deadline is None and attempt.updated_at is not None:
        deadline = attempt.updated_at + datetime.timedelta(
            seconds=settings.notification_attempt_lease_seconds
        )
    return deadline is not None and deadline <= now


def reconcile_stale_notification_attempt(
    db: DBSession,
    session: AgentSession,
) -> NotificationAttempt | None:
    """Turn an abandoned provider call into an explicit, recoverable state."""

    now = datetime.datetime.utcnow()
    stale = next(
        (
            attempt
            for attempt in session.notification_attempts
            if _attempt_is_stale(attempt, now)
        ),
        None,
    )
    if stale is None:
        return None
    stale.status = "ambiguous"
    stale.provider_status = "stale_unknown"
    stale.error_code = "NOTIFICATION_LEASE_EXPIRED"
    stale.error_message = (
        "The provider request did not complete before its lease expired; "
        "delivery is unknown."
    )
    stale.lease_expires_at = None
    session.notification_attempt_id = stale.id
    session.notification_status = "ambiguous"
    session.notified = False
    db.add_all([stale, session])
    db.commit()
    return stale


def _create_attempt_before_io(
    db: DBSession,
    *,
    session: AgentSession,
    contact,
    kind: str,
    channel: str,
    message: str,
    location_url: str | None,
    device: ContactDevice | None = None,
) -> tuple[NotificationAttempt, bool]:
    existing = (
        db.query(NotificationAttempt)
        .filter(
            NotificationAttempt.session_id == session.id,
            NotificationAttempt.contact_id == contact.id,
            NotificationAttempt.kind == kind,
        )
        .first()
    )
    if existing is not None:
        if _attempt_is_stale(existing, datetime.datetime.utcnow()):
            existing.status = "ambiguous"
            existing.provider_status = "stale_unknown"
            existing.error_code = "NOTIFICATION_LEASE_EXPIRED"
            existing.error_message = "Provider delivery is unknown after the request lease expired."
            existing.lease_expires_at = None
            session.notification_attempt_id = existing.id
            session.notification_status = "ambiguous"
            session.notified = False
            db.add_all([existing, session])
            db.commit()
        return existing, False

    attempt = NotificationAttempt(
        session_id=session.id,
        contact_id=contact.id,
        contact_device_id=device.id if device else None,
        kind=kind,
        channel=channel,
        status="sending",
        message=message,
        location_url=location_url,
        lease_expires_at=datetime.datetime.utcnow()
        + datetime.timedelta(seconds=settings.notification_attempt_lease_seconds),
    )
    db.add(attempt)
    try:
        db.commit()
    except IntegrityError:
        # A concurrent worker won the unique (session, contact, kind) race.
        # Reuse its durable attempt instead of crossing the provider boundary twice.
        db.rollback()
        existing = (
            db.query(NotificationAttempt)
            .filter(
                NotificationAttempt.session_id == session.id,
                NotificationAttempt.contact_id == contact.id,
                NotificationAttempt.kind == kind,
            )
            .first()
        )
        if existing is None:  # defensive: preserve the original failure if it was unrelated
            raise
        return existing, False
    db.refresh(attempt)
    # Persist an in-flight marker and lease before crossing the provider
    # boundary. Repeated calls cannot submit a duplicate.
    session.notification_attempt_id = attempt.id
    session.notification_status = "sending"
    db.add_all([attempt, session])
    db.commit()
    return attempt, True


def _finish_attempt(
    db: DBSession,
    session: AgentSession,
    attempt: NotificationAttempt,
    *,
    status: str,
    provider_status: str,
    provider_message_id: str | None = None,
    error_code: str | None = None,
    error_message: str | None = None,
    provider_details: list[dict] | None = None,
) -> None:
    attempt.status = status
    attempt.provider_status = provider_status
    attempt.provider_message_id = provider_message_id
    attempt.error_code = error_code
    attempt.error_message = error_message
    attempt.lease_expires_at = None
    if provider_details is not None:
        attempt.provider_details = provider_details
    if status in _ACCEPTED_STATUSES and attempt.sent_at is None:
        attempt.sent_at = datetime.datetime.utcnow()
    session.notification_attempt_id = attempt.id
    session.notification_status = status
    session.notified = status in _ACCEPTED_STATUSES
    db.add_all([attempt, session])
    db.commit()


def _send_apns(
    db: DBSession,
    session: AgentSession,
    contact,
    devices: list[ContactDevice],
    message: str,
    location_url: str | None,
) -> NotificationAttempt:
    attempt, should_send = _create_attempt_before_io(
        db,
        session=session,
        contact=contact,
        device=None,
        kind="safety_alert_apns",
        channel="apns",
        message=message,
        location_url=location_url,
    )
    if not should_send:
        return attempt
    if not devices:
        _finish_attempt(
            db,
            session,
            attempt,
            status="failed",
            provider_status="no_device",
            error_code="APNS_NO_ACTIVE_DEVICE",
            error_message="Trusted contact has no active APNs device",
        )
        return attempt

    details: list[dict] = []
    last_result = None
    saw_ambiguous = False
    for device in devices:
        result = apns_provider.send(
            device_token=device.device_token,
            environment=device.environment,
            attempt_id=attempt.id,
            session_id=session.id,
            contact_id=contact.id,
            contact_name=contact.name,
        )
        last_result = result
        details.append(
            {
                "device_id": device.id,
                "environment": device.environment,
                "provider_status": result.provider_status,
                "provider_message_id": result.provider_message_id,
                "error_code": result.error_code,
            }
        )
        if result.deactivate_device:
            device.active = False
            db.add(device)
        if result.accepted:
            attempt.contact_device_id = device.id
            _finish_attempt(
                db,
                session,
                attempt,
                status="accepted",
                provider_status=result.provider_status,
                provider_message_id=result.provider_message_id,
                provider_details=details,
            )
            return attempt
        saw_ambiguous = saw_ambiguous or result.provider_status == "request_failed"

    assert last_result is not None
    _finish_attempt(
        db,
        session,
        attempt,
        status="ambiguous" if saw_ambiguous else "failed",
        provider_status="request_failed" if saw_ambiguous else last_result.provider_status,
        provider_message_id=last_result.provider_message_id,
        error_code=last_result.error_code,
        error_message=last_result.error_message,
        provider_details=details,
    )
    return attempt


def _send_twilio(
    db: DBSession,
    session: AgentSession,
    contact,
    message: str,
    location_url: str | None,
) -> NotificationAttempt:
    attempt, should_send = _create_attempt_before_io(
        db,
        session=session,
        contact=contact,
        kind="safety_alert_sms",
        channel="twilio",
        message=message,
        location_url=location_url,
    )
    if not should_send:
        return attempt

    if not contact.sms_fallback_enabled:
        _finish_attempt(
            db,
            session,
            attempt,
            status="failed",
            provider_status="consent_required",
            error_code="TWILIO_SMS_CONSENT_REQUIRED",
            error_message="Trusted contact has not explicitly enabled SMS fallback",
        )
        return attempt

    if not contact.phone_number:
        _finish_attempt(
            db,
            session,
            attempt,
            status="failed",
            provider_status="no_phone_number",
            error_code="TWILIO_NO_PHONE_NUMBER",
            error_message="Trusted contact has no phone number",
        )
        return attempt

    twilio_configured = bool(
        settings.twilio_account_sid
        and settings.twilio_api_key_sid
        and settings.twilio_api_key_secret
        and settings.twilio_from_number
    )
    if not twilio_configured:
        _finish_attempt(
            db,
            session,
            attempt,
            status="failed",
            provider_status="not_configured",
            error_code="TWILIO_NOT_CONFIGURED",
            error_message="Twilio credentials are not configured",
        )
        return attempt

    callback_url = None
    if settings.public_base_url and settings.twilio_auth_token:
        callback_url = (
            f"{settings.public_base_url.rstrip('/')}/webhooks/twilio/status/{attempt.id}"
        )
    create_args = {
        "to": contact.phone_number,
        "from_": settings.twilio_from_number,
        "body": message,
    }
    if callback_url:
        create_args["status_callback"] = callback_url

    try:
        client = Client(
            settings.twilio_api_key_sid,
            settings.twilio_api_key_secret,
            settings.twilio_account_sid,
        )
        result = client.messages.create(**create_args)
        provider_status = result.status or "queued"
        status = provider_status if provider_status in _ACCEPTED_STATUSES else "queued"
        _finish_attempt(
            db,
            session,
            attempt,
            status=status,
            provider_status=provider_status,
            provider_message_id=result.sid,
        )
    except (TwilioRestException, TwilioException) as exc:
        _finish_attempt(
            db,
            session,
            attempt,
            status="failed",
            provider_status="rejected",
            error_code=str(getattr(exc, "code", None) or "TWILIO_REQUEST_FAILED"),
            error_message=str(exc),
        )
    return attempt


def send_sms_fallback(
    db: DBSession,
    session: AgentSession,
) -> NotificationAttempt:
    """Send the one idempotent server SMS after a known or ambiguous APNs failure."""

    if session.status != "SEVERELY_IMPAIRED" or session.confidence < 0.8:
        raise ValueError("SMS fallback requires the severe notification threshold")
    contact = session.event.selected_contact
    if contact is None or contact.invite_status != "accepted":
        raise ValueError("an accepted selected trusted contact is required")
    if not contact.sms_fallback_enabled:
        raise ValueError("the trusted contact has not enabled SMS fallback")
    apns_attempt = (
        db.query(NotificationAttempt)
        .filter(
            NotificationAttempt.session_id == session.id,
            NotificationAttempt.contact_id == contact.id,
            NotificationAttempt.kind == "safety_alert_apns",
        )
        .first()
    )
    if apns_attempt is None or apns_attempt.status not in {"failed", "ambiguous"}:
        raise ValueError("SMS fallback requires a failed or ambiguous APNs attempt")
    location_url = None
    if session.latitude is not None and session.longitude is not None:
        location_url = f"https://maps.google.com/?q={session.latitude},{session.longitude}"
    message = safety_alert_message(session.event.user.name, location_url)
    return _send_twilio(db, session, contact, message, location_url)


def notify_contact(db: DBSession, session: AgentSession, args: dict) -> dict:
    """Alert only the contact selected for this event.

    The model's optional ``message`` argument is intentionally ignored. If an
    older client created an event without a selection, the sole contact is
    selected automatically; multiple contacts always require an explicit choice.
    """

    del args
    if session.status != "SEVERELY_IMPAIRED" or session.confidence < 0.8:
        session.notification_status = "threshold_not_met"
        session.notified = False
        db.add(session)
        db.commit()
        return {
            "acknowledged": False,
            "error": "notification requires SEVERELY_IMPAIRED status and confidence >= 0.8",
            "results": [],
        }

    contact = session.event.selected_contact
    if contact is None:
        contacts = session.event.user.dd_contacts
        if len(contacts) != 1:
            session.notification_status = "contact_required"
            session.notified = False
            db.add(session)
            db.commit()
            return {
                "acknowledged": False,
                "error": "event requires exactly one selected trusted contact",
                "results": [],
            }
        contact = contacts[0]
        session.event.selected_contact_id = contact.id
        db.add(session.event)
        db.commit()

    if contact.invite_status != "accepted":
        session.notification_status = "consent_required"
        session.notified = False
        db.add(session)
        db.commit()
        return {
            "acknowledged": False,
            "error": "selected trusted contact has not accepted the invitation",
            "results": [],
        }

    location_url = None
    if session.latitude is not None and session.longitude is not None:
        location_url = f"https://maps.google.com/?q={session.latitude},{session.longitude}"
    message = safety_alert_message(session.event.user.name, location_url)

    devices = (
        db.query(ContactDevice)
        .filter(ContactDevice.contact_id == contact.id, ContactDevice.active.is_(True))
        .order_by(ContactDevice.updated_at.desc())
        .all()
    )
    attempts = []
    apns_attempt = _send_apns(db, session, contact, devices, message, location_url)
    attempts.append(apns_attempt)
    if apns_attempt.status in {"pending", "sending"}:
        # A different worker owns this provider call. Refresh once in case it
        # just completed; otherwise leave the durable in-flight session state
        # untouched and never race an SMS fallback against it.
        db.refresh(apns_attempt)
        if apns_attempt.status in {"pending", "sending"}:
            return {
                "acknowledged": False,
                "notification_status": apns_attempt.status,
                "notification_attempt_id": apns_attempt.id,
                "results": [_attempt_result(apns_attempt)],
            }

    # Provider acceptance is enough to stop fallback, but is not represented as
    # delivery. The authenticated acknowledgement endpoint is engagement proof.
    # An idempotent concurrent caller may observe the APNs attempt in-flight; it
    # must not race ahead and submit an SMS while the first call is unresolved.
    # A network/timeout failure is ambiguous: APNs may have accepted the push,
    # so never auto-send a duplicate SMS. The owner can explicitly request the
    # consented SMS fallback after seeing that state.
    if apns_attempt.status == "failed" and contact.sms_fallback_enabled:
        twilio_attempt = _send_twilio(db, session, contact, message, location_url)
        attempts.append(twilio_attempt)
        if twilio_attempt.status in {"pending", "sending"}:
            db.refresh(twilio_attempt)
            if twilio_attempt.status in {"pending", "sending"}:
                return {
                    "acknowledged": False,
                    "notification_status": twilio_attempt.status,
                    "notification_attempt_id": twilio_attempt.id,
                    "results": [_attempt_result(attempt) for attempt in attempts],
                }

    successful = next((a for a in reversed(attempts) if a.status in _ACCEPTED_STATUSES), None)
    final_attempt = successful or attempts[-1]
    session.notification_attempt_id = final_attempt.id
    session.notification_status = final_attempt.status
    session.notified = successful is not None
    db.add(session)
    db.commit()
    return {
        "acknowledged": successful is not None,
        "notification_status": session.notification_status,
        "notification_attempt_id": session.notification_attempt_id,
        "results": [_attempt_result(attempt) for attempt in attempts],
    }


HANDLERS = {
    "retrieve_baseline": retrieve_baseline,
    "analyze_deviation": analyze_deviation,
    "update_confidence": update_confidence,
    "request_test": request_test,
    "notify_contact": notify_contact,
}
