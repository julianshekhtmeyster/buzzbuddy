"""Python implementations behind each tool the AI examiner can call.

Each handler takes (db, session, args) and returns a JSON-serializable dict
that gets fed back to the model as the tool result.
"""

from sqlalchemy.orm import Session as DBSession
from twilio.base.exceptions import TwilioRestException
from twilio.rest import Client

from ..config import settings
from ..models import AgentSession, TestResult


def retrieve_baseline(db: DBSession, session: AgentSession, args: dict) -> dict:
    user = session.event.user
    baseline = user.baseline
    if baseline is None:
        return {"error": "no baseline on file for this user"}
    return {
        "reaction_time_ms": baseline.reaction_time_ms,
        "gyro_stability_score": baseline.gyro_stability_score,
        "memory_recall_percent": baseline.memory_recall_percent,
        "weight_kg": user.weight_kg,
        "height_cm": user.height_cm,
        "bmi": user.bmi,
    }


_BASELINE_FIELD_BY_TEST = {
    "reaction": "reaction_time_ms",
    "gyro": "gyro_stability_score",
    "balance": "gyro_stability_score",
    "memory": "memory_recall_percent",
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


# Twilio error 572006: "Invalid template name. Trial accounts can only use
# predefined SMS templates." Trial (unpaid) accounts can't send arbitrary
# text -- only these canned templates. Closest fit to a DD alert we have.
_TWILIO_TRIAL_TEMPLATE_ERROR = 572006
_TWILIO_TRIAL_FALLBACK_BODY = "sms_customer_support"


def notify_contact(db: DBSession, session: AgentSession, args: dict) -> dict:
    contacts = session.event.user.dd_contacts
    message = args["message"]
    if session.latitude is not None and session.longitude is not None:
        message += f"\n\nLocation: https://maps.google.com/?q={session.latitude},{session.longitude}"

    twilio_configured = bool(
        settings.twilio_account_sid
        and settings.twilio_api_key_sid
        and settings.twilio_api_key_secret
        and settings.twilio_from_number
    )
    client = (
        Client(settings.twilio_api_key_sid, settings.twilio_api_key_secret, settings.twilio_account_sid)
        if twilio_configured
        else None
    )

    results = []
    for contact in contacts:
        if not contact.phone_number:
            results.append({"contact": contact.name, "sent": False, "reason": "no phone number on file"})
            continue
        if client is None:
            print(f"[NOTIFY-STUB] Twilio not configured. Would text {contact.name} ({contact.phone_number}): {message}")
            results.append({"contact": contact.name, "sent": False, "reason": "Twilio not configured"})
            continue
        try:
            client.messages.create(to=contact.phone_number, from_=settings.twilio_from_number, body=message)
            results.append({"contact": contact.name, "sent": True})
        except TwilioRestException as e:
            if e.code == _TWILIO_TRIAL_TEMPLATE_ERROR:
                try:
                    client.messages.create(
                        to=contact.phone_number,
                        from_=settings.twilio_from_number,
                        body=_TWILIO_TRIAL_FALLBACK_BODY,
                    )
                    results.append(
                        {
                            "contact": contact.name,
                            "sent": True,
                            "reason": "Twilio trial account: sent generic template, not the custom message",
                        }
                    )
                except TwilioRestException as e2:
                    results.append({"contact": contact.name, "sent": False, "reason": str(e2)})
            else:
                results.append({"contact": contact.name, "sent": False, "reason": str(e)})

    session.notified = True
    db.add(session)
    db.commit()
    return {"acknowledged": True, "results": results}


HANDLERS = {
    "retrieve_baseline": retrieve_baseline,
    "analyze_deviation": analyze_deviation,
    "update_confidence": update_confidence,
    "request_test": request_test,
    "notify_contact": notify_contact,
}
