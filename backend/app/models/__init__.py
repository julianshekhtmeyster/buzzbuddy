import datetime
import uuid

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    JSON,
    String,
    Text,
    UniqueConstraint,
)
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
    access_token_hash = Column(String, nullable=True, index=True)
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
    invite_code = Column(String, unique=True, nullable=True, index=True)
    invite_status = Column(String, nullable=False, default="pending")  # pending | accepted | expired
    invite_expires_at = Column(DateTime, nullable=True)
    accepted_at = Column(DateTime, nullable=True)
    access_token_hash = Column(String, nullable=True, index=True)
    sms_consent = Column(Boolean, nullable=False, default=False)
    sms_consent_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)

    user = relationship("User", back_populates="dd_contacts")
    devices = relationship(
        "ContactDevice",
        back_populates="contact",
        cascade="all, delete-orphan",
        order_by="ContactDevice.updated_at.desc()",
    )
    notification_attempts = relationship("NotificationAttempt", back_populates="contact")
    selected_events = relationship(
        "Event",
        back_populates="selected_contact",
        foreign_keys="Event.selected_contact_id",
    )

    @property
    def has_registered_device(self) -> bool:
        return any(device.active for device in self.devices)

    @property
    def sms_fallback_enabled(self) -> bool:
        return bool(
            self.invite_status == "accepted"
            and self.sms_consent
            and self.phone_number
        )


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
    selected_contact_id = Column(String, ForeignKey("dd_contacts.id"), nullable=True)
    name = Column(String, nullable=False)
    status = Column(String, default="active")  # active | ended
    started_at = Column(DateTime, default=datetime.datetime.utcnow)
    ended_at = Column(DateTime, nullable=True)

    user = relationship("User", back_populates="events")
    selected_contact = relationship(
        "DDContact",
        back_populates="selected_events",
        foreign_keys=[selected_contact_id],
    )
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
    # Detailed notification state. `notified` remains for old clients and is
    # true only after a provider accepts the alert (never for a failed attempt).
    notification_status = Column(String, nullable=False, default="not_requested")
    notification_attempt_id = Column(String, nullable=True)
    # Most recent known device location, updated alongside test-result submissions
    # so it's available if the AI escalates to notify_contact within the same turn.
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)

    event = relationship("Event", back_populates="sessions")
    test_results = relationship("TestResult", back_populates="session")
    notification_attempts = relationship(
        "NotificationAttempt",
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="NotificationAttempt.created_at.desc()",
    )

    @property
    def selected_contact(self):
        return self.event.selected_contact


class TestResult(Base):
    __tablename__ = "test_results"

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("agent_sessions.id"), nullable=False)
    test_type = Column(String, nullable=False)  # reaction | gyro | memory | balance
    raw_value = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)

    session = relationship("AgentSession", back_populates="test_results")


class ContactDevice(Base):
    """An APNs device belonging to an accepted trusted contact."""

    __tablename__ = "contact_devices"
    __table_args__ = (
        UniqueConstraint("contact_id", "device_token", name="uq_contact_device_token"),
    )

    id = Column(String, primary_key=True, default=gen_uuid)
    contact_id = Column(String, ForeignKey("dd_contacts.id"), nullable=False, index=True)
    device_token = Column(String, nullable=False)
    environment = Column(String, nullable=False, default="production")  # sandbox | production
    active = Column(Boolean, nullable=False, default=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)

    contact = relationship("DDContact", back_populates="devices")
    notification_attempts = relationship("NotificationAttempt", back_populates="contact_device")


class NotificationAttempt(Base):
    """Durable record of one provider attempt for a safety alert.

    `kind` makes retries idempotent. APNs and SMS are separate kinds so a
    failed APNs attempt can fall back to one SMS attempt without duplication.
    """

    __tablename__ = "notification_attempts"
    __table_args__ = (
        UniqueConstraint(
            "session_id",
            "contact_id",
            "kind",
            name="uq_notification_attempt_session_contact_kind",
        ),
    )

    id = Column(String, primary_key=True, default=gen_uuid)
    session_id = Column(String, ForeignKey("agent_sessions.id"), nullable=False, index=True)
    contact_id = Column(String, ForeignKey("dd_contacts.id"), nullable=False, index=True)
    contact_device_id = Column(String, ForeignKey("contact_devices.id"), nullable=True)
    kind = Column(String, nullable=False)  # safety_alert_apns | safety_alert_sms
    channel = Column(String, nullable=False)  # apns | twilio
    status = Column(String, nullable=False, default="pending")
    provider_status = Column(String, nullable=True)
    provider_message_id = Column(String, nullable=True, index=True)
    provider_details = Column(JSON, default=list)
    message = Column(Text, nullable=False)
    location_url = Column(String, nullable=True)
    error_code = Column(String, nullable=True)
    error_message = Column(Text, nullable=True)
    lease_expires_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    sent_at = Column(DateTime, nullable=True)
    delivered_at = Column(DateTime, nullable=True)
    acknowledged_at = Column(DateTime, nullable=True)
    acknowledgement_response = Column(String, nullable=True)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)

    session = relationship("AgentSession", back_populates="notification_attempts")
    contact = relationship("DDContact", back_populates="notification_attempts")
    contact_device = relationship("ContactDevice", back_populates="notification_attempts")
