# BuzzBuddy

Hackathon project. Adaptive iOS app that estimates impairment by comparing sensor-based
test results against a user's own **sober baseline** — not by estimating BAC. An
agentic AI "examiner" (DigitalOcean Serverless Inference, OpenAI-compatible tool
calling) reasons over test evidence in a loop and, on high-confidence severe
impairment, texts the user's designated driver (DD) contacts via Twilio.

## Hard constraints (do not relax these)

- **Never** estimate or display BAC. **Never** state or imply the user is legally
  safe/unsafe to drive. The product only reports deviation from the user's own
  baseline. This is enforced in `backend/app/agent/prompts.py` — preserve it in any
  prompt or copy changes.
- Verdict is always one of three levels: `CLEAR`, `MILDLY_IMPAIRED`, `SEVERELY_IMPAIRED`.
- `notify_contact` is a one-way, session-ending action gated on confidence crossing
  ~80% for severe impairment — don't lower that bar casually, it's the "don't cry
  wolf to the DD" safeguard.

## Repo layout

```
backend/            FastAPI + agentic loop (Python)
  app/main.py        app entrypoint
  app/config.py       env-driven Settings (DB url, DO inference key/model, Twilio)
  app/database.py     SQLAlchemy session/engine
  app/models/          ORM models
  app/schemas.py       Pydantic request/response models
  app/routers/api.py   HTTP routes (users, events, sessions, test-results)
  app/agent/
    prompts.py          SYSTEM_PROMPT — the examiner's constraints + workflow
    client.py           DO Serverless Inference client (OpenAI-compatible)
    loop.py             the tool-calling agent loop itself
  app/tools/
    definitions.py       OpenAI-style tool schemas: retrieve_baseline,
                          analyze_deviation, update_confidence, request_test,
                          notify_contact
    handlers.py           Python implementations the loop dispatches to
  alembic/             migrations (sqlite locally, swaps to DO Managed Postgres
                        via DATABASE_URL with no code change)
  Dockerfile            for DigitalOcean App Platform deploy (port 8080)

ios/buzzbuddy/buzzbuddy/
  Features/            tab screens — Home/Events/Ride/Settings are thin stubs
                        (~20-24 lines each) still needing real content
  Features/Testing/testEngine.swift   currently a 7-line stub — needs the actual
                        CoreMotion/reaction-time/memory-recall test engine
  Views/
    OnboardingView.swift        baseline setup flow
    StartEventView.swift        create an event
    SafetyCheckFlowView.swift   the "take the test" session flow
    ReactionTestView.swift      built
    GyroBalanceTestView.swift   built
    VerdictView.swift           shows session result
    (no memory-recall test view yet — reaction + gyro/balance exist, memory doesn't)
  Models/APIModels.swift        Codable structs mirroring backend/app/schemas.py
  Networking/BuzzBuddyAPI.swift  HTTP client for the backend
  Core/Theme.swift
```

## Backend API flow

1. `POST /users` — create user with biometrics + sober baseline (`reaction_time_ms`,
   `gyro_stability_score`, `memory_recall_score`) + DD contacts.
2. `POST /events` — start a night-out event for that user.
3. `POST /events/{event_id}/sessions` — start a check. Runs the first agent turn
   (typically `retrieve_baseline` -> `request_test`). Response's `pending_test`
   tells the app which test to prompt.
4. `POST /sessions/{session_id}/test-results` — submit `{test_type, raw_value}`
   (plus optional lat/lon). Runs the next agent turn: `analyze_deviation` ->
   `update_confidence` -> either another `request_test`, a final verdict, or
   `notify_contact`.
5. `GET /sessions/{session_id}` — poll status/confidence/`reasoning_log`
   (plain-English trace of the model's reasoning at each `update_confidence` call —
   useful for demoing the "why" live).

`test_type` enum across the stack: `reaction`, `gyro`, `memory`, `balance`.

## Local dev

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# .env already exists locally with DATABASE_URL=sqlite:///./buzzbuddy.db
alembic upgrade head
uvicorn app.main:app --reload
```

`DIGITAL_OCEAN_MODEL_ACCESS_KEY` and Twilio creds live in `backend/.env` (gitignored,
not committed — get values from Justin/Julian, don't regenerate blindly). Without
Twilio creds, `notify_contact` degrades gracefully to a console log
(`[NOTIFY-STUB] ...`) so the agent loop still runs end-to-end.

iOS: open `ios/buzzbuddy/buzzbuddy.xcodeproj` in Xcode, point `BuzzBuddyAPI.swift`'s
base URL at the running backend (localhost during dev, DO App Platform URL once
deployed).

## Known gaps / likely next work

- `Features/Testing/testEngine.swift` is a stub — needs real CoreMotion wiring for
  gyro/balance and timer-based reaction capture, matching whatever `raw_value`
  shape `POST /test-results` expects for each `test_type`.
- No memory-recall test view/engine yet on iOS, even though `memory` is a valid
  `test_type` on the backend.
- Home/Events/Ride/Settings tab views are placeholders, not wired to real state.
- DigitalOcean Managed Postgres not provisioned yet — still SQLite locally; swap
  `DATABASE_URL` when ready, no code change needed.
- Live Activity / lock-screen persistent nudge (described in the pitch) not started.

## Team

Shared repo — `julianshekhtmeyster` (teammate) is actively pushing to `main`
alongside Justin. Check `git log`/`git fetch` before assuming file state; don't
clobber in-flight work.
