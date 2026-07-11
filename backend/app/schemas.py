from typing import Optional

from pydantic import BaseModel, Field


class DDContactIn(BaseModel):
    name: str
    phone_number: Optional[str] = None
    email: Optional[str] = None


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
    name: str
    weight_kg: float
    height_cm: float
    bmi: float
    baseline: BaselineIn
    dd_contacts: list[DDContactIn]


class UserOut(BaseModel):
    id: str
    name: str

    class Config:
        from_attributes = True


class EventCreate(BaseModel):
    user_id: str
    name: str


class EventOut(BaseModel):
    id: str
    user_id: str
    name: str
    status: str

    class Config:
        from_attributes = True


class TestResultIn(BaseModel):
    test_type: str
    raw_value: float
    latitude: Optional[float] = None
    longitude: Optional[float] = None


class SessionOut(BaseModel):
    id: str
    event_id: str
    status: str
    confidence: float
    pending_test: Optional[str]
    reasoning_log: list[str]
    notified: bool

    class Config:
        from_attributes = True
