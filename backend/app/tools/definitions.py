"""OpenAI-compatible tool schemas the AI examiner can call.

These are passed as `tools=` to DigitalOcean Serverless Inference
(chat.completions), which uses the same tool-calling format as OpenAI.
"""

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "retrieve_baseline",
            "description": (
                "Fetch the user's sober baseline biometrics and test scores, "
                "captured during pre-event setup. Call this first, before "
                "reasoning about any test result."
            ),
            "parameters": {"type": "object", "properties": {}, "required": []},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "analyze_deviation",
            "description": (
                "Compute how much the user's most recent result for a given test "
                "deviates from their sober baseline for that same test."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "test_type": {
                        "type": "string",
                        "enum": ["reaction", "gyro", "memory", "balance", "gait"],
                    }
                },
                "required": ["test_type"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "update_confidence",
            "description": (
                "Record your updated confidence that the user is impaired, with "
                "your reasoning. Call this after analyzing each new piece of "
                "evidence, even if your conclusion hasn't changed much."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "confidence": {
                        "type": "number",
                        "description": "0.0 to 1.0 confidence that the user is impaired",
                    },
                    "level": {
                        "type": "string",
                        "enum": ["CLEAR", "MILDLY_IMPAIRED", "SEVERELY_IMPAIRED"],
                    },
                    "reasoning": {
                        "type": "string",
                        "description": (
                            "2-3 sentences MAXIMUM, shown directly to the user on "
                            "their phone. E.g. 'Reaction time is 400ms slower than "
                            "baseline and stability dropped 20% -- confidence of "
                            "impairment is now 85%.' No filler or restated context."
                        ),
                    },
                },
                "required": ["confidence", "level", "reasoning"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "request_test",
            "description": (
                "Ask the user to perform one more test because the evidence so "
                "far is inconclusive, or because a prior result looked like a "
                "fluke and you want it repeated. This ends your turn — the app "
                "will prompt the user and call you again once the result is in."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "test_type": {
                        "type": "string",
                        "enum": ["reaction", "gyro", "memory", "balance", "gait"],
                    },
                    "reason": {"type": "string"},
                },
                "required": ["test_type", "reason"],
            },
        },
    },
]
