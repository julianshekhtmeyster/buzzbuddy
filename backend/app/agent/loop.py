import json

from sqlalchemy.orm import Session as DBSession

from ..config import settings
from ..models import AgentSession
from ..tools.definitions import TOOLS
from ..tools.handlers import HANDLERS
from .client import client
from .prompts import SYSTEM_PROMPT

MAX_ITERATIONS = 6
# Tool calls after which we must hand control back to the user (need new sensor
# input, or the session is over) rather than keep looping the model.
BLOCKING_TOOLS = {"request_test", "notify_contact"}


def run_agent_turn(db: DBSession, session: AgentSession, user_event_message: str) -> AgentSession:
    """Advance the agentic examiner loop by one externally-visible turn.

    Runs the model, executing any tool calls it makes, until it either hits a
    blocking tool (request_test / notify_contact), gives a final plain-text
    verdict, or exhausts MAX_ITERATIONS.
    """
    messages = list(session.conversation or [])
    if not messages:
        messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    messages.append({"role": "user", "content": user_event_message})

    for _ in range(MAX_ITERATIONS):
        response = client.chat.completions.create(
            model=settings.do_model_name,
            messages=messages,
            tools=TOOLS,
            max_completion_tokens=1024,
        )
        message = response.choices[0].message
        messages.append(message.model_dump(exclude_none=True))

        if not message.tool_calls:
            break  # model gave a final natural-language verdict

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
    return session
