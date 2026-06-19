"""FastAPI wrapper exposing the agent over HTTP.

Run:
    uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001

The /answer endpoint accepts {question, db, tags?} and returns the
agent's final SQL, the result rows, and per-iteration history.
"""
from __future__ import annotations

import os
from typing import Any

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

load_dotenv()

from agent.graph import AgentState, graph  # noqa: E402
from agent.trace_tags import (  # noqa: E402
    annotate_trace_outcome,
    build_invoke_config,
)

# Langfuse is enabled when keys are set; each /answer gets its own handler so
# last_trace_id is per-request and we can tag iterations after the graph runs.
# Set LANGFUSE_DISABLED=1 during load tests if local Langfuse can't keep up.
_langfuse_enabled = bool(
    os.environ.get("LANGFUSE_PUBLIC_KEY")
    and os.environ.get("LANGFUSE_SECRET_KEY")
    and os.environ.get("LANGFUSE_DISABLED", "").lower() not in ("1", "true", "yes")
)
if _langfuse_enabled:
    from langfuse.langchain import CallbackHandler as _CallbackHandler
else:
    _CallbackHandler = None  # type: ignore[misc, assignment]


def _langfuse_handler() -> Any | None:
    if _CallbackHandler is None:
        return None
    return _CallbackHandler()


app = FastAPI()


class AnswerRequest(BaseModel):
    question: str
    db: str
    tags: dict[str, str] = {}


class AnswerResponse(BaseModel):
    sql: str
    rows: list[list[Any]] | None
    iterations: int
    ok: bool
    error: str | None = None
    history: list[dict[str, Any]] = []


@app.get("/health")
def health() -> dict[str, str | bool]:
    return {"status": "ok", "langfuse_enabled": _langfuse_enabled}


@app.post("/answer", response_model=AnswerResponse)
def answer(req: AnswerRequest) -> AnswerResponse:
    state = AgentState(question=req.question, db_id=req.db)
    handler = _langfuse_handler()
    config = build_invoke_config(req.tags, db_id=req.db, handler=handler)
    try:
        final = graph.invoke(state, config=config)
    except Exception as e:  # noqa: BLE001
        annotate_trace_outcome(handler, iterations=0, ok=False)
        raise HTTPException(status_code=500, detail=f"{type(e).__name__}: {e}") from e

    sql = final.get("sql", "")
    iteration = final.get("iteration", 0)
    history = final.get("history", [])
    execution = final.get("execution")

    if execution is None:
        annotate_trace_outcome(handler, iterations=iteration, ok=False)
        return AnswerResponse(
            sql=sql,
            rows=None,
            iterations=iteration,
            ok=False,
            error="agent produced no execution result",
            history=history,
        )
    if not execution.ok:
        annotate_trace_outcome(handler, iterations=iteration, ok=False)
        return AnswerResponse(
            sql=sql,
            rows=None,
            iterations=iteration,
            ok=False,
            error=execution.error,
            history=history,
        )

    verify_ok = bool(final.get("verify_ok", False))
    verify_issue = str(final.get("verify_issue", "") or "")
    if not verify_ok:
        annotate_trace_outcome(handler, iterations=iteration, ok=False)
        return AnswerResponse(
            sql=sql,
            rows=[list(r) for r in (execution.rows or [])],
            iterations=iteration,
            ok=False,
            error=verify_issue or "verifier rejected final result",
            history=history,
        )

    annotate_trace_outcome(handler, iterations=iteration, ok=True)
    return AnswerResponse(
        sql=sql,
        rows=[list(r) for r in (execution.rows or [])],
        iterations=iteration,
        ok=True,
        history=history,
    )
