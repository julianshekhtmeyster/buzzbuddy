import json

from sqlalchemy.orm import Session as DBSession

from ..config import settings
from ..models import AgentSession
from ..tools.definitions import TOOLS
from ..tools.handlers import HANDLERS
from .client import client
from .prompts import SYSTEM_PROMPT

MAX_ITERATIONS = 6
# Tool calls after which we must hand control back to the user (needs new
# sensor input) rather than keep looping the model.
BLOCKING_TOOLS = {"request_test"}


class AgentTurnStalledError(Exception):
    """Raised when the model never calls a single tool this turn.

    Without a tool call the session can't move (no reasoning recorded, no
    test requested, nothing to notify), so returning it as-is would leave
    the client staring at a session frozen at its DB defaults -- looks like
    a nonsensical "in_progress, 0% confidence" verdict. Better to fail loudly
    so the client's existing retry UI kicks in.
    """


def run_agent_turn(db: DBSession, session: AgentSession, user_event_message: str) -> AgentSession:
    """Advance the agentic examiner loop by one externally-visible turn.

    Runs the model, executing any tool calls it makes, until it either hits a
    blocking tool (request_test / notify_contact), gives a final plain-text
    verdict *after having taken at least one action this turn*, or exhausts
    MAX_ITERATIONS.
    """
    messages = list(session.conversation or [])
    if not messages:
        messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    messages.append({"role": "user", "content": user_event_message})

    made_progress = False

    for _ in range(MAX_ITERATIONS):
        response = client.chat.completions.create(
            model=settings.do_model_name,
            messages=messages,
            tools=TOOLS,
            max_completion_tokens=400,
            # Reasoning here is a lightweight lookup-and-compare over numbers
            # already handed to the model, not a hard problem -- extended
            # thinking just adds latency and (per the DO proxy's quirks)
            # eats into the token budget. Keep responses terse and fast.
            extra_body={"thinking": {"type": "disabled"}},
        )
        message = response.choices[0].message
        messages.append(message.model_dump(exclude_none=True))

        if not message.tool_calls:
            if made_progress:
                # Model gave a final natural-language verdict -- this is the
                # one compressed takeaway shown on the verdict screen,
                # distinct from the per-round reasoning_log trace.
                session.final_summary = message.content
                break
            # The model skipped tool use entirely -- nudge it and retry
            # rather than silently returning a session nothing happened to.
            messages.append(
                {
                    "role": "user",
                    "content": (
                        "You must call a tool to make progress -- retrieve_baseline, "
                        "analyze_deviation, update_confidence, request_test, or "
                        "notify_contact. A plain-text reply isn't visible to the user."
                    ),
                }
            )
            continue

        stop_after_tools = False
        for tool_call in message.tool_calls:
            name = tool_call.function.name
            args = json.loads(tool_call.function.arguments or "{}")
            handler = HANDLERS.get(name)
            result = handler(db, session, args) if handler else {"error": f"unknown tool '{name}'"}
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": tool_call.id,
                    "content": json.dumps(result),
                }
            )
            made_progress = True
            if name in BLOCKING_TOOLS:
                stop_after_tools = True

        session.conversation = messages
        db.add(session)
        db.commit()

        if stop_after_tools:
            break

    session.conversation = messages
    db.add(session)
    db.commit()

    if not made_progress:
        raise AgentTurnStalledError(
            f"AI examiner made no progress in {MAX_ITERATIONS} attempts (session {session.id})"
        )

    return session
