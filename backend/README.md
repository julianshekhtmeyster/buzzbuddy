# BuzzBuddy backend

FastAPI backend + agentic AI examiner, running the "examiner" loop against
DigitalOcean Serverless Inference (OpenAI-compatible tool calling).

## Setup

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in DIGITAL_OCEAN_MODEL_ACCESS_KEY when you have it
alembic upgrade head   # creates buzzbuddy.db (sqlite) locally
uvicorn app.main:app --reload
```

Local dev works with zero DB setup (SQLite, default in `.env.example`). To
point at a real DigitalOcean Managed Postgres instance for deployment, set
`DATABASE_URL` to its connection string and rerun `alembic upgrade head`.

## Getting a Model Access Key

DO console -> **Inference** -> **Serverless Inference** -> **Get Started** tab
-> **Create a Model Access Key**. Paste it into `.env` as
`DIGITAL_OCEAN_MODEL_ACCESS_KEY`.

## API flow

1. `POST /users` — create a user with biometrics, sober baseline, and DD contacts.
2. `POST /events` — start a night-out event for that user.
3. `POST /events/{event_id}/sessions` — start a BuzzBuddy check. Runs the first
   agent turn, which typically calls `retrieve_baseline` then `request_test`.
   Response's `pending_test` tells the app which test to prompt the user for.
4. `POST /sessions/{session_id}/test-results` — submit `{test_type, raw_value}`
   from the iOS sensor test. Runs the next agent turn: `analyze_deviation` ->
   `update_confidence` -> either another `request_test`, a final plain-text
   verdict, or `notify_contact` if severe impairment is confirmed.
5. `GET /sessions/{session_id}` — poll current status/confidence/reasoning log.

`AgentSession.reasoning_log` holds the model's plain-English reasoning trace at
each `update_confidence` call — good for demoing the "why" during judging.

## Deploying

Push to GitHub, connect the repo in DigitalOcean App Platform pointed at
`backend/` with the included `Dockerfile` (listens on port 8080, 120s gunicorn
timeout to give the agent loop room to make multiple LLM calls per request).
Set `DATABASE_URL` and `DIGITAL_OCEAN_MODEL_ACCESS_KEY` as App Platform env vars.
