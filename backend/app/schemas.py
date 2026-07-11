import re
import unicodedata
from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


_NAME_URL_RE = re.compile(
    r"(?i)(?:https?://|www\.|(?:^|\s)\S+\.(?:com|net|org|io|app)(?:[/\s]|$))"
)


def _normalize_person_name(value: str) -> str:
    value = unicodedata.normalize("NFKC", value)
    if any(unicodedata.category(char).startswith("C") for char in value):
        raise ValueError("name cannot contain control characters")
    value = " ".join(value.split())
    if not value:
        raise ValueError("name cannot be blank")
    if len(value) > 80:
        raise ValueError("name must be 80 characters or fewer")
    if _NAME_URL_RE.search(value) or "<" in value or ">" in value:
        raise ValueError("name cannot contain a URL or markup")
    return value


def _normalize_phone_number(value: Optional[str]) -> Optional[str]:
    """Normalize common US input and otherwise require E.164.

    Empty input remains allowed for push-only trusted contacts. Ten-digit US
    numbers are accepted for compatibility with the current iOS onboarding UI.
    """

    if value is None or not value.strip():
        return None
    raw = value.strip()
    digits = re.sub(r"\D", "", raw)
    if raw.startswith("+") and 8 <= len(digits) <= 15:
        return f"+{digits}"
    if len(digits) == 10:
        return f"+1{digits}"
    if len(digits) == 11 and digits.startswith("1"):
        return f"+{digits}"
    raise ValueError("phone_number must be an E.164 number (for example +14155552671)")
class DDContactIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    phone_number: Optional[str] = None
    email: Optional[str] = Field(default=None, max_length=320)

    _normalize_phone = field_validator("phone_number")(_normalize_phone_number)
    _normalize_name = field_validator("name")(_normalize_person_name)


class DDContactOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    name: str
    phone_number: Optional[str]
    email: Optional[str]
    invite_code: Optional[str]
    invite_status: str
    invite_expires_at: Optional[datetime]
    accepted_at: Optional[datetime]
    has_registered_device: bool
    sms_fallback_enabled: bool


class BaselineIn(BaseModel):
    reaction_time_ms: float
    gyro_stability_score: float
    # Recall accuracy as a 0-100 percentage, not a 0-1 proportion.
    memory_recall_percent: float = Field(ge=0, le=100)


class BaselineUpdate(BaseModel):
    """Partial baseline update for PATCH /users/{user_id}/baseline. Only the
    fields actually being (re)captured should be set -- e.g. an existing user
    missing just the memory baseline sends only memory_recall_percent."""

    reaction_time_ms: Optional[float] = None
    gyro_stability_score: Optional[float] = None
    memory_recall_percent: Optional[float] = Field(default=None, ge=0, le=100)


class UserCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    weight_kg: float
    height_cm: float
    bmi: float
    baseline: BaselineIn
    dd_contacts: list[DDContactIn]

    _normalize_name = field_validator("name")(_normalize_person_name)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    dd_contacts: list[DDContactOut] = Field(default_factory=list)


class UserCreateOut(UserOut):
    access_token: str


class EventCreate(BaseModel):
    user_id: str
    name: str = Field(min_length=1, max_length=120)
    selected_contact_id: Optional[str] = None

    @field_validator("name")
    @classmethod
    def strip_event_name(cls, value: str) -> str:
        if any(unicodedata.category(char).startswith("C") for char in value):
            raise ValueError("name cannot contain control characters")
        value = " ".join(value.split())
        if not value:
            raise ValueError("name cannot be blank")
        return value


class EventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    name: str
    status: str
    selected_contact_id: Optional[str]
    selected_contact: Optional[DDContactOut]


class TestResultIn(BaseModel):
    test_type: str
    raw_value: float
    latitude: Optional[float] = Field(default=None, ge=-90, le=90)
    longitude: Optional[float] = Field(default=None, ge=-180, le=180)


class SessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    event_id: str
    status: str
    confidence: float
    pending_test: Optional[str]
    reasoning_log: list[str]
    notified: bool
    notification_status: str
    notification_attempt_id: Optional[str]
    selected_contact: Optional[DDContactOut]


class AcceptInviteIn(BaseModel):
    invite_code: str = Field(min_length=8, max_length=128)
    device_token: Optional[str] = Field(default=None, min_length=32, max_length=512)
    environment: Literal["sandbox", "production"] = "production"
    sms_consent: bool = False
    confirmed_phone_number: Optional[str] = None

    _normalize_confirmed_phone = field_validator("confirmed_phone_number")(
        _normalize_phone_number
    )

    @field_validator("invite_code", "device_token")
    @classmethod
    def strip_tokens(cls, value: Optional[str]) -> Optional[str]:
        return value.strip() if value is not None else None

    @model_validator(mode="after")
    def require_phone_confirmation_for_sms(self):
        if self.sms_consent and not self.confirmed_phone_number:
            raise ValueError("confirmed_phone_number is required when sms_consent is true")
        return self


class ContactAcceptOut(BaseModel):
    contact: DDContactOut
    access_token: str


class RegisterDeviceIn(BaseModel):
    device_token: str = Field(min_length=32, max_length=512)
    environment: Literal["sandbox", "production"]

    @field_validator("device_token")
    @classmethod
    def strip_device_token(cls, value: str) -> str:
        return value.strip()


class ContactDeviceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    contact_id: str
    environment: Literal["sandbox", "production"]
    active: bool
    created_at: datetime
    updated_at: datetime


class NotificationAttemptOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    session_id: str
    contact_id: str
    contact_device_id: Optional[str]
    kind: str
    channel: Literal["apns", "twilio"]
    status: str
    provider_status: Optional[str]
    provider_message_id: Optional[str]
    provider_details: list[dict]
    error_code: Optional[str]
    error_message: Optional[str]
    lease_expires_at: Optional[datetime]
    message: str
    location_url: Optional[str]
    created_at: datetime
    sent_at: Optional[datetime]
    delivered_at: Optional[datetime]
    acknowledged_at: Optional[datetime]
    acknowledgement_response: Optional[str]


class AcknowledgeNotificationIn(BaseModel):
    response: Optional[str] = Field(default=None, max_length=500)
