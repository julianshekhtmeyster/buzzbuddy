"""Client for the separate DO GenAI Agent that answers designated-driver (DD)
questions about a specific session. This is intentionally NOT the examiner
loop in loop.py -- different endpoint, different access key, no tool calling,
and it never decides impairment itself. It only explains already-computed
session data, grounded by its own knowledge base for general policy content
(what tests measure, what confidence levels mean, hard disclaimers)."""

from openai import OpenAI

from ..config import settings
from ..models import AgentSession

_client = OpenAI(base_url=settings.dd_agent_endpoint, api_key=settings.dd_agent_access_key or "not-set")


def _session_context(session: AgentSession) -> str:
    tests = [f"{t.test_type}: raw_value={t.raw_value}" for t in session.test_results]
    return (
        f"Session data: status={session.status}, confidence={session.confidence}, "
        f"notified={session.notified}, tests_run=[{', '.join(tests) or 'none yet'}], "
        f"reasoning_log={session.reasoning_log or []}"
    )


def ask_dd_companion(session: AgentSession, question: str) -> str:
    response = _client.chat.completions.create(
        model="n/a",
        messages=[
            {"role": "user", "content": f"{_session_context(session)}\n\nQuestion from DD: {question}"}
        ],
    )
    return response.choices[0].message.content or ""
