from typing import Optional

from pydantic import BaseModel


class DDContactIn(BaseModel):
    name: str
    phone_number: Optional[str] = None
    email: Optional[str] = None


class BaselineIn(BaseModel):
    reaction_time_ms: float
    gyro_stability_score: float
    memory_recall_score: float


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
