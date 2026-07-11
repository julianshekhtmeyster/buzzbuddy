# BuzzBuddy backend

FastAPI backend + agentic AI examiner, running the examiner loop against
DigitalOcean Serverless Inference (OpenAI-compatible tool calling). Safety
alerts use APNs first and Twilio SMS only as a fallback.

## Setup

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env
alembic upgrade head
uvicorn app.main:app --reload
```

Local development uses SQLite. For DigitalOcean Managed PostgreSQL, set
`DATABASE_URL` to its connection string and run `alembic upgrade head` before
starting the new application version. `Base.metadata.create_all` does not alter
an existing database, so the Alembic step is required for upgrades.

Run the backend tests with:

```bash
pytest -q
```

## DigitalOcean inference

In the DigitalOcean console, open **Inference -> Serverless Inference -> Get
Started**, create a model access key, and set
`DIGITAL_OCEAN_MODEL_ACCESS_KEY`. Select access to the configured
`DO_MODEL_NAME`.

## Trusted-contact alert behavior

An event selects exactly one trusted contact. For compatibility, the API
automatically selects the contact only when the user has exactly one; it never
silently alerts every contact or chooses among multiple contacts.

Automatic notification has two server-side gates:

1. The contact must accept a non-expired, single-use invitation.
2. The examiner session must be `SEVERELY_IMPAIRED` with confidence >= 0.8.

The server constructs fixed, reviewed alert copy and ignores any model-supplied
message. It tries each active APNs device, newest first. A definitive APNs
failure can fall back to Twilio only when the contact explicitly opted into SMS
and confirmed the stored phone number. A timeout is marked `ambiguous` and
requires an explicit owner fallback request, avoiding a possible duplicate. Every
provider attempt is written to the database *before* network I/O and is unique
per `(session_id, contact_id, kind)`, preventing repeated agent calls from
submitting duplicate alerts.

Status semantics are explicit:

- `sending`: durable attempt exists and provider I/O is in progress.
- `accepted`: APNs accepted the request. This is **not** delivery proof.
- `queued` / `sent` / `delivered`: Twilio provider states.
- `failed` / `undelivered`: the contact must not be shown as notified.
- `ambiguous`: the provider call timed out or its durable lease expired, so
  delivery is unknown and no automatic SMS is sent.
- `acknowledged`: the trusted contact authenticated and responded in BuzzBuddy;
  this is the strongest evidence that a person engaged with the alert.

The legacy `SessionOut.notified` field remains for older clients. It is never
set on failure, but new clients should display `notification_status` rather than
turning the Boolean into a delivery claim.

## APNs setup

Create an APNs signing key in the Apple Developer portal and set:

```dotenv
APNS_KEY_ID=...
APNS_TEAM_ID=...
APNS_BUNDLE_ID=com.yourcompany.buzzbuddy
APNS_PRIVATE_KEY_BASE64=... # base64 of the .p8 file
```

`APNS_PRIVATE_KEY` (PEM text, including literal `\n`) and
`APNS_PRIVATE_KEY_PATH` are also supported. A DEBUG app should register its
token with `environment: "sandbox"`; release/TestFlight builds use
`environment: "production"`.

APNs lock-screen text is intentionally generic. The push contains only
`notification_attempt_id`, `contact_id`, and the category
`BUZZBUDDY_SAFETY_ALERT`; the app fetches alert details from the authenticated
inbox. APNs `410`, `BadDeviceToken`, and `Unregistered` responses deactivate the
device token.

## Twilio fallback setup

Set the Account SID, API key SID/secret, sender number, and the separate Account
Auth Token:

```dotenv
TWILIO_ACCOUNT_SID=...
TWILIO_API_KEY_SID=...
TWILIO_API_KEY_SECRET=...
TWILIO_AUTH_TOKEN=... # validates Twilio webhook signatures
TWILIO_FROM_NUMBER=+15555555555
PUBLIC_BASE_URL=https://your-app.ondigitalocean.app
```

`PUBLIC_BASE_URL` lets outbound messages register the callback
`/webhooks/twilio/status/{attempt_id}`. The callback validates
`X-Twilio-Signature`, matches `MessageSid`, and applies statuses monotonically
so a late `queued` callback cannot overwrite `delivered`.

Twilio trial accounts generally cannot send the custom BuzzBuddy alert to
arbitrary contacts. There is deliberately no canned `sms_customer_support`
substitution: an irrelevant template is recorded as failure rather than falsely
reported as a safety alert. APNs remains usable without Twilio once the trusted
contact has installed the app and accepted the invitation.

## API contract

### Owner-facing setup and authentication

`POST /users` keeps its original request and returns `dd_contacts` plus an
`access_token` exactly once. Store this token in the device Keychain; only its
SHA-256 hash is stored by the server. Each new contact includes a one-use `invite_code`,
`invite_status: "pending"`, and `invite_expires_at` (seven days by default).
Ten-digit US phone input is normalized to E.164; other non-empty numbers must
already be valid E.164.

The owner bearer token is required for contact listing, event/session creation,
test submission, session polling, invite replacement, and server SMS fallback.
`POST /contacts/{contact_id}/invite` replaces an expired or consumed invitation
and revokes the prior contact credential and registered devices.

`POST /events` accepts:

```json
{
  "user_id": "...",
  "name": "Friday night",
  "selected_contact_id": "..."
}
```

`selected_contact_id` is optional only for compatibility. It must belong to the
event user. `EventOut` adds `selected_contact_id` and `selected_contact`.

### Contact acceptance and device registration

`POST /contacts/accept`

```json
{
  "invite_code": "...",
  "device_token": "optional APNs token",
  "environment": "sandbox",
  "sms_consent": true,
  "confirmed_phone_number": "+14155552671"
}
```

Returns the bearer credential exactly once:

```json
{
  "contact": { "id": "...", "invite_status": "accepted" },
  "access_token": "store-this-in-the-keychain"
}
```

The invite code is cleared on acceptance and cannot be reused. Only a SHA-256
hash of the access token is stored. SMS consent is optional; when enabled, the
confirmed normalized number must exactly match the invitation. The following contact-side routes require
`Authorization: Bearer <access_token>`:

- `POST /contacts/{contact_id}/devices` with
  `{ "device_token": "...", "environment": "sandbox|production" }`.
- `GET /contacts/{contact_id}/notifications` returns
  `NotificationAttemptOut[]`; device tokens are never returned.
- `POST /notifications/{attempt_id}/acknowledge` with an optional
  `{ "response": "I'm responding" }`.

`NotificationAttemptOut` contains `id`, `session_id`, `contact_id`, optional
`contact_device_id`, `kind`, `channel`, `status`, `provider_status`, optional
provider ID/error fields, fixed `message`, optional `location_url`, and delivery
and acknowledgement timestamps.

### Examiner flow

1. `POST /events/{event_id}/sessions` starts a check.
2. `POST /sessions/{session_id}/test-results` submits sensor data.
3. `GET /sessions/{session_id}` polls state.
4. `POST /sessions/{session_id}/notifications/fallback` explicitly requests the
   idempotent, consented SMS after failed or ambiguous APNs delivery.

`SessionOut` keeps every original field and adds `notification_status`,
`notification_attempt_id`, and `selected_contact`.

## Deploying on DigitalOcean

Connect the repository to App Platform with the source directory set to
`backend/`. The included Dockerfile listens on port 8080. Configure the database,
inference key, APNs secrets, and optional Twilio secrets as encrypted environment
variables. Run `alembic upgrade head` as a deployment/release job before routing
traffic to the new image.
