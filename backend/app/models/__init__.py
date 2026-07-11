import datetime
import uuid

from sqlalchemy import Boolean, Column, DateTime, Float, ForeignKey, JSON, String
from sqlalchemy.orm import relationship

from ..database import Base


def gen_uuid() -> str:
    return str(uuid.uuid4())


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=gen_uuid)
    name = Column(String, nullable=False)
    weight_kg = Column(Float, nullable=False)
    height_cm = Column(Float, nullable=False)
    bmi = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

    baseline = relationship("Baseline", back_populates="user", uselist=False)
    dd_contacts = relationship("DDContact", back_populates="user")
    events = relationship("Event", back_populates="user")


class DDContact(Base):
    __tablename__ = "dd_contacts"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    name = Column(String, nullable=False)
    phone_number = Column(String, nullable=True)
    email = Column(String, nullable=True)

    user = relationship("User", back_populates="dd_contacts")


class Baseline(Base):
    """A user's "100% sober" fingerprint, captured once during pre-event setup."""

    __tablename__ = "baselines"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), unique=True, nullable=False)
    reaction_time_ms = Column(Float, nullable=False)
    gyro_stability_score = Column(Float, nullable=False)
    # Python attribute renamed to `memory_recall_percent` -- the value is a
    # 0-100 percentage, not a 0-1 proportion. The SQL column name is kept as
    # `memory_recall_score` to avoid an Alembic migration. Rows created
    # before this rename may still hold stale 0-1-scale placeholder values;
    # those get corrected the next time that user completes the
    # baseline-upgrade flow (PATCH /users/{user_id}/baseline).
    memory_recall_percent = Column("memory_recall_score", Float, nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

    user = relationship("User", back_populates="baseline")


class Event(Base):
    """A single night-out session the user opts into ("Pre-Party Setup")."""

    __tablename__ = "events"

    id = Column(String, primary_key=True, default=gen_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False)
    name = Column(String, nullable=False)
    status = Column(String, default="active")  # active | ended
    started_at = Column(DateTime, default=datetime.datetime.utcnow)
    ended_at = Column(DateTime, nullable=True)

    user = relationship("User", back_populates="events")
    sessions = relationship("AgentSession", back_populates="event")


class AgentSession(Base):
    """One run of the AI examiner: created each time the user takes the BuzzBuddy test."""

    __tablename__ = "agent_sessions"

    id = Column(String, primary_key=True, default=gen_uuid)
    event_id = Column(String, ForeignKey("events.id"), nullable=False)
    status = Column(String, default="in_progress")  # in_progress | clear | mild | severe
    confidence = Column(Float, default=0.0)
    pending_test = Column(String, nullable=True)  # test_type the AI wants next, or None
    reasoning_log = Column(JSON, default=list)  # human-readable trace for the UI/demo
    conversation = Column(JSON, default=list)  # full chat history incl. tool calls, for the loop
    notified = Column(Boolean, default=False)
    # Most recent known device location, updated alongside test-result submissions
    # so it's available if the AI escalates to notify_contact within the same turn.
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)

    event = relationship("Event", back_populates="sessions")
    test_results = relationship("TestResult", back_populates="session")


class TestResult(Base):
    __tablename__ = "test_results"

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("agent_sessions.id"), nullable=False)
    test_type = Column(String, nullable=False)  # reaction | gyro | memory | balance
    raw_value = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

    session = relationship("AgentSession", back_populates="test_results")
