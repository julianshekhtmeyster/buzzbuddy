import datetime
import hashlib
import hmac
import secrets
from urllib.parse import parse_qs

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from openai import OpenAIError
from sqlalchemy.orm import Session as DBSession
from twilio.request_validator import RequestValidator

from ..agent.loop import run_agent_turn
from ..config import settings
from ..database import get_db
from ..models import (
    AgentSession,
    Baseline,
    ContactDevice,
    DDContact,
    Event,
    NotificationAttempt,
    TestResult,
    User,
)
from ..schemas import (
    AcceptInviteIn,
    AcknowledgeNotificationIn,
    ContactAcceptOut,
    ContactDeviceOut,
    DDContactOut,
    EventCreate,
    EventOut,
    NotificationAttemptOut,
    RegisterDeviceIn,
    SessionOut,
    TestResultIn,
    UserCreate,
    UserCreateOut,
)
from ..tools.handlers import reconcile_stale_notification_attempt, send_sms_fallback

router = APIRouter()
contact_bearer = HTTPBearer(auto_error=False)

_PROVIDER_ACCEPTED_STATUSES = {"accepted", "queued", "sent", "delivered", "acknowledged"}
_CONTACT_VISIBLE_STATUSES = _PROVIDER_ACCEPTED_STATUSES | {"ambiguous"}


def _utcnow() -> datetime.datetime:
    return datetime.datetime.utcnow()


def _hash_access_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _new_invite_code() -> str:
    return secrets.token_urlsafe(18)


def _new_access_token() -> str:
    return secrets.token_urlsafe(32)


def _verify_contact_access(
    contact: DDContact,
    credentials: HTTPAuthorizationCredentials | None,
) -> None:
    if (
        credentials is None
        or credentials.scheme.lower() != "bearer"
        or contact.access_token_hash is None
        or not hmac.compare_digest(
            contact.access_token_hash,
            _hash_access_token(credentials.credentials),
        )
    ):
        raise HTTPException(status_code=401, detail="invalid or missing contact access token")


def _verify_owner_access(
    user: User,
    credentials: HTTPAuthorizationCredentials | None,
) -> None:
    if (
        credentials is None
        or credentials.scheme.lower() != "bearer"
        or user.access_token_hash is None
        or not hmac.compare_digest(
            user.access_token_hash,
            _hash_access_token(credentials.credentials),
        )
    ):
        raise HTTPException(status_code=401, detail="invalid or missing owner access token")


def _authorized_contact(
    contact_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
) -> DDContact:
    contact = db.get(DDContact, contact_id)
    if contact is None:
        raise HTTPException(status_code=404, detail="contact not found")
    _verify_contact_access(contact, credentials)
    return contact


def _register_or_reactivate_device(
    db: DBSession,
    contact: DDContact,
    device_token: str,
    environment: str,
) -> ContactDevice:
    device = (
        db.query(ContactDevice)
        .filter(
            ContactDevice.contact_id == contact.id,
            ContactDevice.device_token == device_token,
        )
        .first()
    )
    if device is None:
        device = ContactDevice(
            contact_id=contact.id,
            device_token=device_token,
            environment=environment,
            active=True,
        )
    else:
        device.environment = environment
        device.active = True
        device.updated_at = _utcnow()
    db.add(device)
    return device


def _run_agent_turn_or_502(db: DBSession, session: AgentSession, message: str) -> AgentSession:
    try:
        return run_agent_turn(db, session, message)
    except OpenAIError as e:
        raise HTTPException(status_code=502, detail=f"AI examiner call failed: {e}")


@router.post("/users", response_model=UserCreateOut)
def create_user(payload: UserCreate, db: DBSession = Depends(get_db)):
    access_token = _new_access_token()
    user = User(
        name=payload.name,
        weight_kg=payload.weight_kg,
        height_cm=payload.height_cm,
        bmi=payload.bmi,
        access_token_hash=_hash_access_token(access_token),
    )
    db.add(user)
    db.flush()

    db.add(
        Baseline(
            user_id=user.id,
            reaction_time_ms=payload.baseline.reaction_time_ms,
            gyro_stability_score=payload.baseline.gyro_stability_score,
            memory_recall_score=payload.baseline.memory_recall_score,
        )
    )
    invite_expiry = _utcnow() + datetime.timedelta(hours=settings.contact_invite_ttl_hours)
    for contact in payload.dd_contacts:
        db.add(
            DDContact(
                user_id=user.id,
                **contact.model_dump(),
                invite_code=_new_invite_code(),
                invite_status="pending",
                invite_expires_at=invite_expiry,
            )
        )

    db.commit()
    db.refresh(user)
    return UserCreateOut(
        id=user.id,
        name=user.name,
        dd_contacts=[DDContactOut.model_validate(contact) for contact in user.dd_contacts],
        access_token=access_token,
    )


@router.get("/users/{user_id}/contacts", response_model=list[DDContactOut])
def list_contacts(
    user_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    _verify_owner_access(user, credentials)
    return (
        db.query(DDContact)
        .filter(DDContact.user_id == user_id)
        .order_by(DDContact.created_at.asc())
        .all()
    )


@router.post("/contacts/{contact_id}/invite", response_model=DDContactOut)
def reissue_contact_invite(
    contact_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
):
    contact = db.get(DDContact, contact_id)
    if contact is None:
        raise HTTPException(status_code=404, detail="contact not found")
    _verify_owner_access(contact.user, credentials)
    contact.invite_code = _new_invite_code()
    contact.invite_status = "pending"
    contact.invite_expires_at = _utcnow() + datetime.timedelta(
        hours=settings.contact_invite_ttl_hours
    )
    contact.accepted_at = None
    contact.access_token_hash = None
    contact.sms_consent = False
    contact.sms_consent_at = None
    for device in contact.devices:
        device.active = False
        db.add(device)
    db.add(contact)
    db.commit()
    db.refresh(contact)
    return contact


@router.post("/contacts/accept", response_model=ContactAcceptOut)
def accept_contact_invite(payload: AcceptInviteIn, db: DBSession = Depends(get_db)):
    contact = (
        db.query(DDContact)
        .filter(DDContact.invite_code == payload.invite_code)
        .with_for_update()
        .first()
    )
    if contact is None or contact.invite_status != "pending":
        # A consumed invite is intentionally indistinguishable from a bad code.
        raise HTTPException(status_code=404, detail="invite not found")
    if contact.invite_expires_at is not None and contact.invite_expires_at <= _utcnow():
        contact.invite_status = "expired"
        contact.invite_code = None
        db.add(contact)
        db.commit()
        raise HTTPException(status_code=410, detail="invite expired")

    if payload.sms_consent:
        if contact.phone_number is None:
            raise HTTPException(status_code=400, detail="contact has no phone number for SMS fallback")
        if not hmac.compare_digest(contact.phone_number, payload.confirmed_phone_number or ""):
            raise HTTPException(status_code=400, detail="confirmed phone number does not match invitation")

    access_token = _new_access_token()
    contact.invite_status = "accepted"
    contact.accepted_at = _utcnow()
    contact.invite_code = None  # one-use invite
    contact.invite_expires_at = None
    contact.access_token_hash = _hash_access_token(access_token)
    contact.sms_consent = payload.sms_consent
    contact.sms_consent_at = _utcnow() if payload.sms_consent else None
    db.add(contact)
    if payload.device_token:
        _register_or_reactivate_device(
            db,
            contact,
            payload.device_token,
            payload.environment,
        )
    db.commit()
    db.refresh(contact)
    return ContactAcceptOut(contact=DDContactOut.model_validate(contact), access_token=access_token)


@router.post("/contacts/{contact_id}/devices", response_model=ContactDeviceOut)
def register_contact_device(
    payload: RegisterDeviceIn,
    contact: DDContact = Depends(_authorized_contact),
    db: DBSession = Depends(get_db),
):
    if contact.invite_status != "accepted":
        raise HTTPException(status_code=409, detail="contact invitation has not been accepted")
    device = _register_or_reactivate_device(
        db,
        contact,
        payload.device_token,
        payload.environment,
    )
    db.commit()
    db.refresh(device)
    return device


@router.get(
    "/contacts/{contact_id}/notifications",
    response_model=list[NotificationAttemptOut],
)
def list_contact_notifications(
    contact: DDContact = Depends(_authorized_contact),
    db: DBSession = Depends(get_db),
):
    return (
        db.query(NotificationAttempt)
        .filter(
            NotificationAttempt.contact_id == contact.id,
            NotificationAttempt.status.in_(_CONTACT_VISIBLE_STATUSES),
        )
        .order_by(NotificationAttempt.created_at.desc())
        .all()
    )


@router.post(
    "/notifications/{attempt_id}/acknowledge",
    response_model=NotificationAttemptOut,
)
def acknowledge_notification(
    attempt_id: str,
    payload: AcknowledgeNotificationIn,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
):
    attempt = db.get(NotificationAttempt, attempt_id)
    if attempt is None:
        raise HTTPException(status_code=404, detail="notification not found")
    _verify_contact_access(attempt.contact, credentials)
    if attempt.status not in _CONTACT_VISIBLE_STATUSES:
        raise HTTPException(status_code=409, detail="a failed notification cannot be acknowledged")

    attempt.status = "acknowledged"
    attempt.acknowledged_at = attempt.acknowledged_at or _utcnow()
    attempt.acknowledgement_response = payload.response
    attempt.session.notification_status = "acknowledged"
    attempt.session.notification_attempt_id = attempt.id
    attempt.session.notified = True
    db.add_all([attempt, attempt.session])
    db.commit()
    db.refresh(attempt)
    return attempt


@router.post("/events", response_model=EventOut)
def create_event(
    payload: EventCreate,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
):
    user = db.get(User, payload.user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    _verify_owner_access(user, credentials)
    if user.baseline is None:
        raise HTTPException(status_code=400, detail="user has no baseline on file")

    selected_contact_id = payload.selected_contact_id
    if selected_contact_id is not None:
        contact = db.get(DDContact, selected_contact_id)
        if contact is None or contact.user_id != user.id:
            raise HTTPException(
                status_code=400,
                detail="selected_contact_id must belong to the event user",
            )
    elif len(user.dd_contacts) == 1:
        # Backward compatibility for the current iOS client, which creates one
        # contact and does not yet send selected_contact_id.
        selected_contact_id = user.dd_contacts[0].id

    event = Event(
        user_id=user.id,
        name=payload.name,
        selected_contact_id=selected_contact_id,
    )
    db.add(event)
    db.commit()
    db.refresh(event)
    return event


@router.post("/events/{event_id}/sessions", response_model=SessionOut)
def start_session(
    event_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
):
    event = db.get(Event, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="event not found")
    _verify_owner_access(event.user, credentials)
    if event.status != "active":
        raise HTTPException(status_code=400, detail="event is not active")

    session = AgentSession(event_id=event.id)
    db.add(session)
    db.commit()
    db.refresh(session)

    session = _run_agent_turn_or_502(
        db,
        session,
        "The event has started and the user wants to check in before deciding "
        "whether to drive. Begin the sobriety check by requesting the first test.",
    )
    return session


@router.post("/sessions/{session_id}/test-results", response_model=SessionOut)
def submit_test_result(
    session_id: str,
    payload: TestResultIn,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
):
    session = db.get(AgentSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="session not found")
    _verify_owner_access(session.event.user, credentials)
    # `status` (clear/mild/severe) is the AI's evolving confidence label, not a
    # lifecycle flag — it can say "severe" while still wanting a cross-check
    # test before concluding. The session is actually over only once the DD
    # has been notified, or the AI stopped requesting further tests.
    if session.notified:
        raise HTTPException(status_code=400, detail="session already concluded: designated driver was notified")
    if session.pending_test is None:
        raise HTTPException(status_code=400, detail="session already concluded: no further test was requested")

    db.add(TestResult(session_id=session.id, test_type=payload.test_type, raw_value=payload.raw_value))
    session.pending_test = None
    if payload.latitude is not None and payload.longitude is not None:
        session.latitude = payload.latitude
        session.longitude = payload.longitude
    db.commit()

    session = _run_agent_turn_or_502(
        db,
        session,
        f"The user completed the '{payload.test_type}' test with a raw sensor "
        f"value of {payload.raw_value}. Analyze it and decide the next step.",
    )
    return session


@router.get("/sessions/{session_id}", response_model=SessionOut)
def get_session(
    session_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
):
    session = db.get(AgentSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="session not found")
    _verify_owner_access(session.event.user, credentials)
    reconcile_stale_notification_attempt(db, session)
    return session


@router.post("/sessions/{session_id}/notifications/fallback", response_model=SessionOut)
def request_notification_fallback(
    session_id: str,
    credentials: HTTPAuthorizationCredentials | None = Depends(contact_bearer),
    db: DBSession = Depends(get_db),
):
    session = db.get(AgentSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="session not found")
    _verify_owner_access(session.event.user, credentials)
    reconcile_stale_notification_attempt(db, session)
    try:
        send_sms_fallback(db, session)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    db.refresh(session)
    return session


@router.post("/webhooks/twilio/status/{attempt_id}")
async def twilio_status_callback(
    attempt_id: str,
    request: Request,
    db: DBSession = Depends(get_db),
):
    """Record a Twilio delivery transition after validating its signature."""

    if not settings.twilio_auth_token:
        raise HTTPException(status_code=503, detail="Twilio callback validation is not configured")
    signature = request.headers.get("X-Twilio-Signature")
    if not signature:
        raise HTTPException(status_code=401, detail="missing Twilio signature")

    raw_body = (await request.body()).decode("utf-8")
    parsed = parse_qs(raw_body, keep_blank_values=True)
    params = {key: values[-1] for key, values in parsed.items()}
    if settings.public_base_url:
        callback_url = f"{settings.public_base_url.rstrip('/')}{request.url.path}"
        if request.url.query:
            callback_url += f"?{request.url.query}"
    else:
        callback_url = str(request.url)
    if not RequestValidator(settings.twilio_auth_token).validate(
        callback_url,
        params,
        signature,
    ):
        raise HTTPException(status_code=401, detail="invalid Twilio signature")

    attempt = db.get(NotificationAttempt, attempt_id)
    if attempt is None or attempt.channel != "twilio":
        raise HTTPException(status_code=404, detail="notification not found")
    message_sid = params.get("MessageSid")
    if not message_sid or message_sid != attempt.provider_message_id:
        raise HTTPException(status_code=400, detail="MessageSid does not match notification")

    provider_status = params.get("MessageStatus", "unknown").lower()

    # Do not erase stronger proof if a delayed callback arrives after an app ack.
    if attempt.status != "acknowledged":
        success_rank = {
            "accepted": 1,
            "scheduled": 1,
            "queued": 1,
            "sent": 2,
            "delivered": 3,
        }
        current_rank = success_rank.get(attempt.provider_status or "", 0)
        incoming_rank = success_rank.get(provider_status, 0)
        # Success callbacks can arrive out of order. Once Twilio reports sent or
        # delivered, a delayed queued callback must not regress the record.
        if incoming_rank and incoming_rank < current_rank:
            return {"acknowledged": True, "ignored": "stale status"}
        # Delivery is terminal even if a delayed failure callback is received.
        if attempt.status == "delivered" and provider_status in {
            "failed",
            "undelivered",
            "canceled",
        }:
            return {"acknowledged": True, "ignored": "stale terminal status"}

        attempt.provider_status = provider_status
        attempt.error_code = params.get("ErrorCode") or None
        attempt.error_message = params.get("ErrorMessage") or None
        if provider_status == "delivered":
            attempt.status = "delivered"
            attempt.delivered_at = _utcnow()
        elif provider_status in {"failed", "undelivered", "canceled"}:
            attempt.status = "undelivered" if provider_status == "undelivered" else "failed"
        elif provider_status in {"sent", "queued", "accepted", "scheduled"}:
            attempt.status = "queued" if provider_status in {"accepted", "scheduled"} else provider_status

        attempt.session.notification_status = attempt.status
        attempt.session.notification_attempt_id = attempt.id
        attempt.session.notified = attempt.status in _PROVIDER_ACCEPTED_STATUSES

    db.add_all([attempt, attempt.session])
    db.commit()
    return {"acknowledged": True}
