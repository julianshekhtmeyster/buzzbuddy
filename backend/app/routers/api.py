from fastapi import APIRouter, Depends, HTTPException
from openai import OpenAIError
from sqlalchemy.orm import Session as DBSession

from ..agent.dd_companion import ask_dd_companion
from ..agent.loop import AgentTurnStalledError, run_agent_turn
from ..database import get_db
from ..models import AgentSession, Baseline, DDContact, Event, TestResult, User
from ..schemas import (
    BaselineUpdate,
    DDChatRequest,
    DDChatResponse,
    EventCreate,
    EventOut,
    SessionOut,
    TestResultIn,
    UserCreate,
    UserOut,
)

router = APIRouter()


def _run_agent_turn_or_502(db: DBSession, session: AgentSession, message: str) -> AgentSession:
    try:
        return run_agent_turn(db, session, message)
    except OpenAIError as e:
        raise HTTPException(status_code=502, detail=f"AI examiner call failed: {e}")
    except AgentTurnStalledError as e:
        raise HTTPException(status_code=502, detail=str(e))


@router.post("/users", response_model=UserOut)
def create_user(payload: UserCreate, db: DBSession = Depends(get_db)):
    user = User(
        name=payload.name,
        weight_kg=payload.weight_kg,
        height_cm=payload.height_cm,
        bmi=payload.bmi,
    )
    db.add(user)
    db.flush()

    if payload.baseline is not None:
        db.add(
            Baseline(
                user_id=user.id,
                reaction_time_ms=payload.baseline.reaction_time_ms,
                gyro_stability_score=payload.baseline.gyro_stability_score,
                memory_recall_percent=payload.baseline.memory_recall_percent,
            )
        )
    for contact in payload.dd_contacts:
        db.add(DDContact(user_id=user.id, **contact.model_dump()))

    db.commit()
    db.refresh(user)
    return user


@router.patch("/users/{user_id}/baseline", response_model=UserOut)
def update_baseline(user_id: str, payload: BaselineUpdate, db: DBSession = Depends(get_db)):
    """Updates the existing user's baseline in place -- used to backfill a
    baseline (e.g. memory) that didn't exist when the user first onboarded.
    Never creates a duplicate user. Only the fields present in the payload
    are touched; anything omitted keeps its current value."""
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")

    updates = payload.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(status_code=400, detail="no baseline fields provided")

    if user.baseline is None:
        required = {"reaction_time_ms", "gyro_stability_score", "memory_recall_percent"}
        missing = required - updates.keys()
        if missing:
            raise HTTPException(
                status_code=400,
                detail=f"user has no baseline on file; must provide all fields, missing: {sorted(missing)}",
            )
        db.add(Baseline(user_id=user.id, **updates))
    else:
        for field, value in updates.items():
            setattr(user.baseline, field, value)
        db.add(user.baseline)

    db.commit()
    db.refresh(user)
    return user


@router.post("/events", response_model=EventOut)
def create_event(payload: EventCreate, db: DBSession = Depends(get_db)):
    user = db.get(User, payload.user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    if user.baseline is None:
        raise HTTPException(status_code=400, detail="user has no baseline on file")

    event = Event(user_id=user.id, name=payload.name)
    db.add(event)
    db.commit()
    db.refresh(event)
    return event


@router.post("/events/{event_id}/sessions", response_model=SessionOut)
def start_session(event_id: str, db: DBSession = Depends(get_db)):
    event = db.get(Event, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="event not found")
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
def submit_test_result(session_id: str, payload: TestResultIn, db: DBSession = Depends(get_db)):
    session = db.get(AgentSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="session not found")
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
def get_session(session_id: str, db: DBSession = Depends(get_db)):
    session = db.get(AgentSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="session not found")
    return session


@router.post("/sessions/{session_id}/dd-chat", response_model=DDChatResponse)
def dd_chat(session_id: str, payload: DDChatRequest, db: DBSession = Depends(get_db)):
    """Lets a designated driver ask questions about a concluded (or
    in-progress) session. Uses a separate DO agent from the examiner loop --
    read-only, no tool calling, never decides impairment itself."""
    session = db.get(AgentSession, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="session not found")
    try:
        answer = ask_dd_companion(session, payload.question)
    except OpenAIError as e:
        raise HTTPException(status_code=502, detail=f"DD companion call failed: {e}")
    return DDChatResponse(answer=answer)
