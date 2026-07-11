import os
import sys
import tempfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


_database_file = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
_database_file.close()
os.environ["DATABASE_URL"] = f"sqlite:///{_database_file.name}"
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.database import Base, SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True)
def clean_database():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def user_payload():
    return {
        "name": "Alex",
        "weight_kg": 70,
        "height_cm": 175,
        "bmi": 22.9,
        "baseline": {
            "reaction_time_ms": 250,
            "gyro_stability_score": 0.2,
            "memory_recall_percent": 90,
        },
        "dd_contacts": [
            {
                "name": "Sam",
                "phone_number": "(415) 555-2671",
                "email": "sam@example.com",
            }
        ],
    }


@pytest.fixture
def accepted_contact(client, user_payload):
    user_response = client.post("/users", json=user_payload)
    assert user_response.status_code == 200, user_response.text
    contact = user_response.json()["dd_contacts"][0]
    accept_response = client.post(
        "/contacts/accept",
        json={
            "invite_code": contact["invite_code"],
            "device_token": "a" * 64,
            "environment": "sandbox",
            "sms_consent": True,
            "confirmed_phone_number": "+14155552671",
        },
    )
    assert accept_response.status_code == 200, accept_response.text
    accepted = accept_response.json()
    return {
        "user": user_response.json(),
        "contact": accepted["contact"],
        "access_token": accepted["access_token"],
        "owner_access_token": user_response.json()["access_token"],
    }
