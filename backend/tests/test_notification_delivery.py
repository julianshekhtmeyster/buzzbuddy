import datetime

from twilio.request_validator import RequestValidator

from app.config import settings
from app.models import AgentSession, ContactDevice, DDContact, Event, NotificationAttempt
from app.notifications import APNsResult
from app.tools import handlers


def _severe_session(db, contact_id: str) -> AgentSession:
    contact = db.get(DDContact, contact_id)
    event = Event(user_id=contact.user_id, name="Test", selected_contact_id=contact.id)
    db.add(event)
    db.flush()
    session = AgentSession(
        event_id=event.id,
        status="SEVERELY_IMPAIRED",
        confidence=0.91,
        latitude=37.77,
        longitude=-122.42,
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return session


def test_apns_acceptance_is_recorded_once_and_message_is_server_controlled(
    db,
    accepted_contact,
    monkeypatch,
):
    session = _severe_session(db, accepted_contact["contact"]["id"])
    calls = []

    def fake_send(**kwargs):
        calls.append(kwargs)
        return APNsResult(
            accepted=True,
            provider_status="accepted",
            provider_message_id=kwargs["attempt_id"],
        )

    monkeypatch.setattr(handlers.apns_provider, "send", fake_send)
    first = handlers.notify_contact(db, session, {"message": "MALICIOUS MODEL COPY"})
    second = handlers.notify_contact(db, session, {"message": "different"})

    assert first["acknowledged"] is True
    assert second["acknowledged"] is True
    assert session.notified is True
    assert session.notification_status == "accepted"
    assert len(calls) == 1
    assert calls[0]["environment"] == "sandbox"
    attempts = db.query(NotificationAttempt).all()
    assert len(attempts) == 1
    assert attempts[0].status == "accepted"  # APNs acceptance is not delivery
    assert "MALICIOUS" not in attempts[0].message
    assert "BuzzBuddy safety alert" in attempts[0].message
    assert attempts[0].location_url.endswith("37.77,-122.42")


def test_failed_apns_and_unconfigured_twilio_never_mark_notified(
    db,
    accepted_contact,
    monkeypatch,
):
    session = _severe_session(db, accepted_contact["contact"]["id"])
    monkeypatch.setattr(
        handlers.apns_provider,
        "send",
        lambda **_: APNsResult(
            accepted=False,
            provider_status="rejected",
            error_code="BadDeviceToken",
            error_message="bad token",
            deactivate_device=True,
        ),
    )
    monkeypatch.setattr(settings, "twilio_account_sid", "")

    result = handlers.notify_contact(db, session, {})

    assert result["acknowledged"] is False
    assert session.notified is False
    assert session.notification_status == "failed"
    attempts = db.query(NotificationAttempt).order_by(NotificationAttempt.created_at).all()
    assert [attempt.channel for attempt in attempts] == ["apns", "twilio"]
    assert attempts[0].error_code == "BadDeviceToken"
    assert all(device.active is False for device in attempts[0].contact.devices)
    assert attempts[1].error_code == "TWILIO_NOT_CONFIGURED"


def test_inflight_apns_attempt_does_not_race_a_twilio_fallback(
    db,
    accepted_contact,
    monkeypatch,
):
    session = _severe_session(db, accepted_contact["contact"]["id"])
    attempt = NotificationAttempt(
        session_id=session.id,
        contact_id=accepted_contact["contact"]["id"],
        contact_device_id=session.event.selected_contact.devices[0].id,
        kind="safety_alert_apns",
        channel="apns",
        status="sending",
        message="Details",
    )
    session.notification_status = "sending"
    db.add_all([attempt, session])
    db.commit()
    monkeypatch.setattr(
        handlers.apns_provider,
        "send",
        lambda **_: (_ for _ in ()).throw(AssertionError("must not resend")),
    )

    result = handlers.notify_contact(db, session, {})

    assert result["notification_status"] == "sending"
    assert db.query(NotificationAttempt).count() == 1
    assert db.query(NotificationAttempt).filter_by(channel="twilio").count() == 0


def test_notification_requires_threshold_and_contact_consent(db, client, user_payload):
    user = client.post("/users", json=user_payload).json()
    contact_id = user["dd_contacts"][0]["id"]
    session = _severe_session(db, contact_id)

    result = handlers.notify_contact(db, session, {})
    assert result["acknowledged"] is False
    assert session.notification_status == "consent_required"
    assert db.query(NotificationAttempt).count() == 0

    contact = db.get(DDContact, contact_id)
    contact.invite_status = "accepted"
    session.status = "MILDLY_IMPAIRED"
    session.confidence = 0.99
    db.commit()
    result = handlers.notify_contact(db, session, {})
    assert result["acknowledged"] is False
    assert session.notification_status == "threshold_not_met"
    assert db.query(NotificationAttempt).count() == 0


def test_sms_is_never_attempted_without_contact_sms_consent(db, client, user_payload):
    user = client.post("/users", json=user_payload).json()
    contact_data = user["dd_contacts"][0]
    accepted = client.post(
        "/contacts/accept", json={"invite_code": contact_data["invite_code"]}
    )
    assert accepted.status_code == 200
    session = _severe_session(db, contact_data["id"])

    result = handlers.notify_contact(db, session, {})

    assert result["acknowledged"] is False
    assert db.query(NotificationAttempt).filter_by(channel="apns").count() == 1
    assert db.query(NotificationAttempt).filter_by(channel="twilio").count() == 0

def test_authenticated_acknowledgement_updates_attempt_and_session(
    client,
    db,
    accepted_contact,
):
    session = _severe_session(db, accepted_contact["contact"]["id"])
    attempt = NotificationAttempt(
        session_id=session.id,
        contact_id=accepted_contact["contact"]["id"],
        kind="safety_alert_apns",
        channel="apns",
        status="accepted",
        provider_status="accepted",
        message="Details",
    )
    db.add(attempt)
    db.commit()

    assert client.post(
        f"/notifications/{attempt.id}/acknowledge",
        json={"response": "I'm responding"},
    ).status_code == 401
    response = client.post(
        f"/notifications/{attempt.id}/acknowledge",
        json={"response": "I'm responding"},
        headers={"Authorization": f"Bearer {accepted_contact['access_token']}"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "acknowledged"
    assert response.json()["acknowledgement_response"] == "I'm responding"
    db.refresh(session)
    assert session.notification_status == "acknowledged"


def test_signed_twilio_callback_cannot_regress_delivered_status(
    client,
    db,
    accepted_contact,
    monkeypatch,
):
    session = _severe_session(db, accepted_contact["contact"]["id"])
    attempt = NotificationAttempt(
        session_id=session.id,
        contact_id=accepted_contact["contact"]["id"],
        kind="safety_alert_sms",
        channel="twilio",
        status="queued",
        provider_status="queued",
        provider_message_id="SM123",
        message="Details",
    )
    db.add(attempt)
    db.commit()

    monkeypatch.setattr(settings, "twilio_auth_token", "callback-secret")
    monkeypatch.setattr(settings, "public_base_url", "http://testserver")
    url = f"http://testserver/webhooks/twilio/status/{attempt.id}"

    def post_status(status):
        data = {"MessageSid": "SM123", "MessageStatus": status}
        signature = RequestValidator("callback-secret").compute_signature(url, data)
        return client.post(
            f"/webhooks/twilio/status/{attempt.id}",
            data=data,
            headers={"X-Twilio-Signature": signature},
        )

    assert post_status("delivered").status_code == 200
    stale = post_status("queued")
    assert stale.status_code == 200
    db.refresh(attempt)
    assert attempt.status == "delivered"
    assert attempt.provider_status == "delivered"


def test_apns_tries_all_active_devices_until_one_accepts(db, accepted_contact, monkeypatch):
    contact = db.get(DDContact, accepted_contact["contact"]["id"])
    contact.devices[0].updated_at = datetime.datetime.utcnow() - datetime.timedelta(minutes=1)
    second = ContactDevice(
        contact_id=contact.id,
        device_token="e" * 64,
        environment="production",
        active=True,
        updated_at=datetime.datetime.utcnow(),
    )
    db.add(second)
    db.commit()
    calls = []

    def fake_send(**kwargs):
        calls.append(kwargs["device_token"])
        if len(calls) == 1:
            return APNsResult(
                accepted=False,
                provider_status="rejected",
                error_code="BadDeviceToken",
                deactivate_device=True,
            )
        return APNsResult(accepted=True, provider_status="accepted", provider_message_id="ok")

    monkeypatch.setattr(handlers.apns_provider, "send", fake_send)
    session = _severe_session(db, contact.id)
    result = handlers.notify_contact(db, session, {})

    assert result["acknowledged"] is True
    assert len(calls) == 2
    attempt = db.query(NotificationAttempt).one()
    assert attempt.status == "accepted"
    assert len(attempt.provider_details) == 2


def test_expired_attempt_lease_becomes_ambiguous_and_can_be_acknowledged(
    client, db, accepted_contact
):
    session = _severe_session(db, accepted_contact["contact"]["id"])
    attempt = NotificationAttempt(
        session_id=session.id,
        contact_id=accepted_contact["contact"]["id"],
        kind="safety_alert_apns",
        channel="apns",
        status="sending",
        lease_expires_at=datetime.datetime.utcnow() - datetime.timedelta(seconds=1),
        message="Details",
    )
    db.add(attempt)
    db.commit()

    owner_headers = {"Authorization": f"Bearer {accepted_contact['owner_access_token']}"}
    refreshed = client.get(f"/sessions/{session.id}", headers=owner_headers)
    assert refreshed.status_code == 200, refreshed.text
    assert refreshed.json()["notification_status"] == "ambiguous"

    contact_headers = {"Authorization": f"Bearer {accepted_contact['access_token']}"}
    inbox = client.get(
        f"/contacts/{accepted_contact['contact']['id']}/notifications",
        headers=contact_headers,
    )
    assert [item["id"] for item in inbox.json()] == [attempt.id]
    acknowledged = client.post(
        f"/notifications/{attempt.id}/acknowledge",
        json={"response": "I'm responding"},
        headers=contact_headers,
    )
    assert acknowledged.status_code == 200, acknowledged.text


def test_owner_can_request_one_consented_sms_after_ambiguous_apns(
    client, db, accepted_contact, monkeypatch
):
    session = _severe_session(db, accepted_contact["contact"]["id"])
    attempt = NotificationAttempt(
        session_id=session.id,
        contact_id=accepted_contact["contact"]["id"],
        kind="safety_alert_apns",
        channel="apns",
        status="ambiguous",
        provider_status="request_failed",
        message="Details",
    )
    db.add(attempt)
    db.commit()
    sends = []

    class FakeMessages:
        def create(self, **kwargs):
            sends.append(kwargs)
            return type("Message", (), {"status": "queued", "sid": "SM-fallback"})()

    class FakeClient:
        messages = FakeMessages()

    monkeypatch.setattr(handlers, "Client", lambda *_: FakeClient())
    monkeypatch.setattr(settings, "twilio_account_sid", "AC-test")
    monkeypatch.setattr(settings, "twilio_api_key_sid", "SK-test")
    monkeypatch.setattr(settings, "twilio_api_key_secret", "secret")
    monkeypatch.setattr(settings, "twilio_from_number", "+14155550000")
    owner_headers = {"Authorization": f"Bearer {accepted_contact['owner_access_token']}"}

    first = client.post(
        f"/sessions/{session.id}/notifications/fallback", headers=owner_headers
    )
    second = client.post(
        f"/sessions/{session.id}/notifications/fallback", headers=owner_headers
    )
    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text
    assert first.json()["notification_status"] == "queued"
    assert len(sends) == 1
