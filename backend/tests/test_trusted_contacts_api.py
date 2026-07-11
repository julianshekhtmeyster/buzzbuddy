def test_accept_invite_is_single_use_and_contact_routes_require_bearer(client, user_payload):
    response = client.post("/users", json=user_payload)
    assert response.status_code == 200
    user = response.json()
    contact = user["dd_contacts"][0]
    assert contact["phone_number"] == "+14155552671"
    assert contact["invite_status"] == "pending"
    invite_code = contact["invite_code"]

    response = client.post(
        "/contacts/accept",
        json={
            "invite_code": invite_code,
            "device_token": "b" * 64,
            "environment": "sandbox",
        },
    )
    assert response.status_code == 200
    accepted = response.json()
    assert accepted["contact"]["invite_code"] is None
    assert accepted["contact"]["invite_status"] == "accepted"
    assert accepted["contact"]["has_registered_device"] is True
    assert len(accepted["access_token"]) >= 32

    assert client.post("/contacts/accept", json={"invite_code": invite_code}).status_code == 404
    inbox_url = f"/contacts/{contact['id']}/notifications"
    assert client.get(inbox_url).status_code == 401
    assert client.get(inbox_url, headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.get(
        inbox_url,
        headers={"Authorization": f"Bearer {accepted['access_token']}"},
    ).status_code == 200

    device_response = client.post(
        f"/contacts/{contact['id']}/devices",
        json={"device_token": "c" * 64, "environment": "production"},
        headers={"Authorization": f"Bearer {accepted['access_token']}"},
    )
    assert device_response.status_code == 200
    assert "device_token" not in device_response.json()


def test_event_selection_must_belong_to_user(client, user_payload):
    first = client.post("/users", json=user_payload).json()
    second_payload = {**user_payload, "name": "Taylor"}
    second = client.post("/users", json=second_payload).json()

    bad = client.post(
        "/events",
        json={
            "user_id": first["id"],
            "name": "Friday",
            "selected_contact_id": second["dd_contacts"][0]["id"],
        },
        headers={"Authorization": f"Bearer {first['access_token']}"},
    )
    assert bad.status_code == 400

    good = client.post(
        "/events",
        json={
            "user_id": first["id"],
            "name": "Friday",
            "selected_contact_id": first["dd_contacts"][0]["id"],
        },
        headers={"Authorization": f"Bearer {first['access_token']}"},
    )
    assert good.status_code == 200
    assert good.json()["selected_contact_id"] == first["dd_contacts"][0]["id"]


def test_one_contact_is_selected_for_legacy_event_payload(client, user_payload):
    user = client.post("/users", json=user_payload).json()
    event = client.post(
        "/events",
        json={"user_id": user["id"], "name": "Legacy client event"},
        headers={"Authorization": f"Bearer {user['access_token']}"},
    )
    assert event.status_code == 200
    assert event.json()["selected_contact_id"] == user["dd_contacts"][0]["id"]


def test_owner_routes_require_owner_token_and_reissue_revokes_contact(client, user_payload):
    user = client.post("/users", json=user_payload).json()
    contact = user["dd_contacts"][0]
    owner_headers = {"Authorization": f"Bearer {user['access_token']}"}

    assert client.get(f"/users/{user['id']}/contacts").status_code == 401
    assert client.get(
        f"/users/{user['id']}/contacts", headers=owner_headers
    ).status_code == 200

    acceptance = client.post(
        "/contacts/accept",
        json={"invite_code": contact["invite_code"], "device_token": "d" * 64},
    ).json()
    contact_headers = {"Authorization": f"Bearer {acceptance['access_token']}"}
    assert client.get(
        f"/users/{user['id']}/contacts", headers=contact_headers
    ).status_code == 401

    reissued = client.post(
        f"/contacts/{contact['id']}/invite", headers=owner_headers
    )
    assert reissued.status_code == 200, reissued.text
    assert reissued.json()["invite_status"] == "pending"
    assert reissued.json()["invite_code"]
    assert reissued.json()["has_registered_device"] is False
    assert client.get(
        f"/contacts/{contact['id']}/notifications", headers=contact_headers
    ).status_code == 401


def test_sms_consent_requires_matching_phone_without_consuming_invite(client, user_payload):
    user = client.post("/users", json=user_payload).json()
    contact = user["dd_contacts"][0]
    rejected = client.post(
        "/contacts/accept",
        json={
            "invite_code": contact["invite_code"],
            "sms_consent": True,
            "confirmed_phone_number": "+14155550000",
        },
    )
    assert rejected.status_code == 400

    accepted = client.post(
        "/contacts/accept",
        json={
            "invite_code": contact["invite_code"],
            "sms_consent": True,
            "confirmed_phone_number": "(415) 555-2671",
        },
    )
    assert accepted.status_code == 200, accepted.text
    assert accepted.json()["contact"]["sms_fallback_enabled"] is True


def test_person_names_reject_notification_injection(client, user_payload):
    payload = {**user_payload, "name": "Alex\nhttps://attacker.example"}
    assert client.post("/users", json=payload).status_code == 422
