"""Notification-provider helpers.

Provider acceptance is deliberately distinct from delivery. APNs HTTP 200 is
recorded as ``accepted``; only the trusted contact's authenticated acknowledgement
is treated as proof that a person engaged with the alert.
"""

import base64
import binascii
import time
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import httpx
import jwt

from .config import settings


@dataclass(frozen=True)
class APNsResult:
    accepted: bool
    provider_status: str
    provider_message_id: Optional[str] = None
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    deactivate_device: bool = False


class APNsProvider:
    """Small token-authenticated APNs HTTP/2 client."""

    def __init__(self) -> None:
        self._jwt: Optional[str] = None
        self._jwt_created_at = 0.0

    @property
    def configured(self) -> bool:
        return bool(
            settings.apns_key_id
            and settings.apns_team_id
            and settings.apns_bundle_id
            and (
                settings.apns_private_key
                or settings.apns_private_key_base64
                or settings.apns_private_key_path
            )
        )

    def _private_key(self) -> str:
        if settings.apns_private_key_base64:
            return base64.b64decode(settings.apns_private_key_base64).decode("utf-8")
        if settings.apns_private_key:
            return settings.apns_private_key.replace("\\n", "\n")
        return Path(settings.apns_private_key_path).read_text(encoding="utf-8")

    def _authorization_token(self) -> str:
        # Apple allows provider tokens for up to one hour. Refresh a little early.
        now = time.time()
        if self._jwt and now - self._jwt_created_at < 50 * 60:
            return self._jwt
        self._jwt = jwt.encode(
            {"iss": settings.apns_team_id, "iat": int(now)},
            self._private_key(),
            algorithm="ES256",
            headers={"kid": settings.apns_key_id},
        )
        self._jwt_created_at = now
        return self._jwt

    def send(
        self,
        *,
        device_token: str,
        environment: str,
        attempt_id: str,
        session_id: str,
        contact_id: str,
        contact_name: str,
    ) -> APNsResult:
        if not self.configured:
            return APNsResult(
                accepted=False,
                provider_status="not_configured",
                error_code="APNS_NOT_CONFIGURED",
                error_message="APNs credentials are not configured",
            )

        host = "api.sandbox.push.apple.com" if environment == "sandbox" else "api.push.apple.com"
        url = f"https://{host}/3/device/{device_token}"
        # Keep lock-screen copy intentionally generic. Details are retrieved from
        # the authenticated inbox using the opaque attempt ID.
        payload = {
            "aps": {
                "alert": {
                    "title": "BuzzBuddy safety check",
                    "body": "Someone asked you to check in. Open BuzzBuddy for details.",
                },
                "sound": "default",
                "category": "BUZZBUDDY_SAFETY_ALERT",
            },
            "notification_attempt_id": attempt_id,
            "contact_id": contact_id,
        }
        try:
            authorization_token = self._authorization_token()
        except (OSError, ValueError, binascii.Error, jwt.PyJWTError) as exc:
            return APNsResult(
                accepted=False,
                provider_status="credential_error",
                error_code="APNS_CREDENTIAL_ERROR",
                error_message=str(exc),
            )

        headers = {
            "authorization": f"bearer {authorization_token}",
            "apns-topic": settings.apns_bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "apns-expiration": str(int(time.time() + 60 * 60)),
            # Collapse repeated sends for the same safety-check session.
            "apns-collapse-id": f"buzzbuddy-{session_id}",
            "apns-id": attempt_id,
        }

        try:
            with httpx.Client(http2=True, timeout=settings.notification_timeout_seconds) as client:
                response = client.post(url, headers=headers, json=payload)
        except (httpx.HTTPError, OSError, ValueError) as exc:
            return APNsResult(
                accepted=False,
                provider_status="request_failed",
                error_code="APNS_REQUEST_FAILED",
                error_message=str(exc),
            )

        provider_id = response.headers.get("apns-id") or attempt_id
        if response.status_code == 200:
            return APNsResult(
                accepted=True,
                provider_status="accepted",
                provider_message_id=provider_id,
            )

        try:
            reason = response.json().get("reason", f"HTTP {response.status_code}")
        except (ValueError, AttributeError):
            reason = f"HTTP {response.status_code}"
        return APNsResult(
            accepted=False,
            provider_status="rejected",
            provider_message_id=provider_id,
            error_code=str(reason),
            error_message=f"APNs rejected the notification ({response.status_code})",
            deactivate_device=response.status_code == 410 or reason in {"BadDeviceToken", "Unregistered"},
        )


apns_provider = APNsProvider()


def safety_alert_message(user_name: str, location_url: Optional[str]) -> str:
    """Build reviewed copy on the server; model-supplied prose is never sent."""

    # New records are validated at the API boundary, but deployments may have
    # older names in the database. Never let legacy control characters, markup,
    # or URL-like text enter an outbound SMS.
    safe_name = "Your friend"
    normalized = " ".join(unicodedata.normalize("NFKC", user_name).split())
    if (
        normalized
        and len(normalized) <= 80
        and not any(unicodedata.category(char).startswith("C") for char in normalized)
        and "<" not in normalized
        and ">" not in normalized
        and "://" not in normalized
        and "www." not in normalized.lower()
    ):
        safe_name = normalized

    message = (
        f"BuzzBuddy safety alert: {safe_name} asked you to be their trusted contact. "
        "Their safety check showed a significant change from their personal baseline. "
        "Please contact them and help arrange a safe ride. BuzzBuddy does not estimate "
        "BAC or legal fitness to drive. Reply STOP to opt out."
    )
    if location_url:
        message += f" Location: {location_url}"
    return message
