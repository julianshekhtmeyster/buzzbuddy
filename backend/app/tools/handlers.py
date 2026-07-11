"""Python implementations behind each tool the AI examiner can call.

Each handler takes (db, session, args) and returns a JSON-serializable dict
that gets fed back to the model as the tool result.
"""

from sqlalchemy.orm import Session as DBSession

from ..models import AgentSession, TestResult


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


def notify_contact(db: DBSession, session: AgentSession, args: dict) -> dict:
    contacts = session.event.user.dd_contacts
    # Stub: swap for a real SMS/push integration (Twilio, APNs) before demo day.
    for contact in contacts:
        print(f"[NOTIFY] {contact.name} ({contact.phone_number or contact.email}): {args['message']}")
    session.notified = True
    db.add(session)
    db.commit()
    return {"acknowledged": True, "notified_count": len(contacts)}


HANDLERS = {
    "retrieve_baseline": retrieve_baseline,
    "analyze_deviation": analyze_deviation,
    "update_confidence": update_confidence,
    "request_test": request_test,
    "notify_contact": notify_contact,
}
