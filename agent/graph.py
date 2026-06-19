"""LangGraph agent: text-to-SQL with verify+revise loop.

Graph shape:

    START -> attach_schema -> generate_sql -> execute -> verify
                                                          |
                                              ok=true ----+----> END
                                                          |
                                              ok=false ---+----> revise -> execute -> verify (loop)

Loop is capped at MAX_ITERATIONS total generate/revise calls.

The execute node and the graph wiring are provided. `generate_sql_node` is
filled in as a worked example; you implement `verify`, `revise`, and the
conditional router following the same shape.
"""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from typing import Any

from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph

from agent import prompts
from agent.execution import ExecutionResult, execute_sql
from agent.schema import render_schema

# Total generate + revise calls before the loop is forced to stop.
# 3-5 is a reasonable range; tune it as part of Phase 3.
MAX_ITERATIONS = int(os.environ.get("MAX_ITERATIONS", "3"))

VLLM_BASE_URL = os.environ.get("VLLM_BASE_URL", "http://localhost:8000/v1")
VLLM_MODEL = os.environ.get("VLLM_MODEL", "Qwen/Qwen3-30B-A3B-Instruct-2507")
# vLLM ignores the key, but a hosted OpenAI-compatible provider needs a real one.
# Lets you point the agent at e.g. OpenAI while iterating without a running vLLM.
LLM_API_KEY = (
    os.environ.get("OPENAI_API_KEY")
    or os.environ.get("NEBIUS_API_KEY")
    or "not-needed"
)


@dataclass
class AgentState:
    """State threaded through the graph. Extend with fields you need."""

    question: str
    db_id: str
    schema: str = ""
    sql: str = ""
    execution: ExecutionResult | None = None
    verify_ok: bool = False
    verify_issue: str = ""
    iteration: int = 0
    history: list[dict[str, Any]] = field(default_factory=list)


def _llm_extra_body() -> dict[str, Any]:
    """Disable Qwen3 chain-of-thought; otherwise revise returns prose as SQL."""
    if "qwen3" in VLLM_MODEL.lower():
        return {"chat_template_kwargs": {"enable_thinking": False}}
    return {}


def llm(*, max_tokens: int = 256) -> ChatOpenAI:
    """Chat client pointed at VLLM_BASE_URL (your local vLLM by default).

    Default completion budget is modest — BIRD schema prompts are large and
    local vLLM often runs with --max-model-len 2048–4096.
    """
    return ChatOpenAI(
        model=VLLM_MODEL,
        base_url=VLLM_BASE_URL,
        api_key=LLM_API_KEY,
        temperature=0.0,
        max_tokens=max_tokens,
        extra_body=_llm_extra_body(),
    )


# ---- Nodes ------------------------------------------------------------

def _attach_schema(state: AgentState) -> dict:
    """Provided. Render the DB schema once at the start of the run."""
    return {"schema": render_schema(state.db_id)}


def _strip_thinking(text: str) -> str:
    """Remove Qwen3 reasoning blocks before parsing SQL or JSON."""
    for open_tag, close_tag in (
        ("<" + "think" + ">", "</" + "think" + ">"),
        ("<think>", "</think>"),
    ):
        text = re.sub(
            re.escape(open_tag) + r".*?" + re.escape(close_tag),
            "",
            text,
            flags=re.DOTALL | re.IGNORECASE,
        )
    return text.strip()


def _table_list(schema: str) -> str:
    """Comma-separated table names from rendered CREATE TABLE schema text."""
    names = re.findall(r"CREATE TABLE \"([^\"]+)\"", schema)
    return ", ".join(names)


def _prior_sql(history: list[dict[str, Any]]) -> str:
    """Summarize failed SQL attempts for the revise prompt."""
    lines: list[str] = []
    for entry in history:
        if entry.get("node") in ("generate_sql", "revise") and entry.get("sql"):
            lines.append(entry["sql"])
    if not lines:
        return "None"
    return "\n---\n".join(lines)


def _extract_sql(text: str) -> str:
    """Pull a SQL statement out of an LLM reply, stripping thinking/fences/prose."""
    text = _strip_thinking(text)
    fenced = re.search(r"```(?:sql)?\s*(.*?)```", text, re.DOTALL | re.IGNORECASE)
    if fenced:
        return fenced.group(1).strip()

    match = re.search(r"(SELECT\b.+?)(?:;|\Z)", text, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip().rstrip(";")

    return text.strip()


def _parse_json_object(text: str) -> dict[str, Any] | None:
    """Extract a JSON object from an LLM reply, tolerating fences or prose."""
    stripped = _strip_thinking(text.strip())
    try:
        parsed = json.loads(stripped)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", stripped, re.DOTALL | re.IGNORECASE)
    if fenced:
        try:
            parsed = json.loads(fenced.group(1))
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass

    match = re.search(r"\{[^{}]*\}", stripped, re.DOTALL)
    if match:
        try:
            parsed = json.loads(match.group(0))
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass
    return None


def generate_sql_node(state: AgentState) -> dict:
    """Worked example - the other LLM nodes follow this same shape.

    Build messages from the prompts, call the shared llm(), extract the SQL,
    and return only the state fields you changed. `iteration` is bumped here
    (and in revise) so route_after_verify can enforce MAX_ITERATIONS.

    This node is wired and ready; fill in GENERATE_SQL_SYSTEM / GENERATE_SQL_USER
    in prompts.py to make it produce real queries.
    """
    response = llm().invoke([
        ("system", prompts.GENERATE_SQL_SYSTEM),
        ("user", prompts.GENERATE_SQL_USER.format(
            schema=state.schema,
            question=state.question,
            table_list=_table_list(state.schema),
        )),
    ])
    sql = _extract_sql(response.content)
    return {
        "sql": sql,
        "iteration": state.iteration + 1,
        "history": state.history + [{"node": "generate_sql", "sql": sql}],
    }


def execute_node(state: AgentState) -> dict:
    """Provided. Runs the SQL and stores the result."""
    return {"execution": execute_sql(state.db_id, state.sql)}


def verify_node(state: AgentState) -> dict:
    """Decide whether state.execution plausibly answers state.question.

    Follow the generate_sql_node pattern: build messages from the VERIFY_*
    prompts, call llm(), parse the reply. Ask the model for a small JSON object
    like {"ok": bool, "issue": str} and parse it defensively - the model may
    wrap it in prose or fences. state.execution.render() gives you a compact
    view of the rows or error to feed into the prompt.

    Return: {"verify_ok": <bool>, "verify_issue": <str>}.
    What counts as "not plausible" is yours to define - see the Phase 3 targets
    in the README.
    """
    execution = state.execution
    if execution is None:
        return {
            "verify_ok": False,
            "verify_issue": "no execution result",
            "history": state.history + [{"node": "verify", "ok": False, "issue": "no execution result"}],
        }

    if not execution.ok:
        issue = execution.error or "SQL execution failed"
        return {
            "verify_ok": False,
            "verify_issue": issue,
            "history": state.history + [{"node": "verify", "ok": False, "issue": issue}],
        }

    execution_result = execution.render()
    response = llm(max_tokens=128).invoke([
        ("system", prompts.VERIFY_SYSTEM),
        ("user", prompts.VERIFY_USER.format(
            question=state.question,
            sql=state.sql,
            execution_result=execution_result,
        )),
    ])
    content = response.content if isinstance(response.content, str) else str(response.content)
    parsed = _parse_json_object(content)
    if parsed is None:
        issue = "could not parse verifier output"
        return {
            "verify_ok": False,
            "verify_issue": issue,
            "history": state.history + [{"node": "verify", "ok": False, "issue": issue}],
        }

    verify_ok = bool(parsed.get("ok", False))
    verify_issue = str(parsed.get("issue", "") or "")
    return {
        "verify_ok": verify_ok,
        "verify_issue": verify_issue,
        "history": state.history + [{"node": "verify", "ok": verify_ok, "issue": verify_issue}],
    }


def revise_node(state: AgentState) -> dict:
    """Produce a revised SQL query given state.verify_issue and the prior attempt.

    Same shape as generate_sql_node, but the prompt should include the failing
    SQL, its execution result, and the verifier's complaint so the model can fix
    it. Bump the iteration counter the same way generate_sql_node does so the
    loop terminates.

    Return: {"sql": <str>, "iteration": state.iteration + 1, ...}.
    """
    execution_result = state.execution.render() if state.execution else "No execution result."
    response = llm().invoke([
        ("system", prompts.REVISE_SYSTEM),
        ("user", prompts.REVISE_USER.format(
            schema=state.schema,
            question=state.question,
            table_list=_table_list(state.schema),
            prior_sql=_prior_sql(state.history),
            sql=state.sql,
            execution_result=execution_result,
            issue=state.verify_issue,
        )),
    ])
    sql = _extract_sql(response.content)
    return {
        "sql": sql,
        "iteration": state.iteration + 1,
        "history": state.history + [{
            "node": "revise",
            "sql": sql,
            "issue": state.verify_issue,
        }],
    }


def route_after_verify(state: AgentState) -> str:
    """Conditional router: return "revise" to loop, "end" to terminate.

    Two reasons to end: the verifier was happy (state.verify_ok), or you've hit
    the iteration cap (state.iteration >= MAX_ITERATIONS). Otherwise, revise.
    """
    if state.verify_ok or state.iteration >= MAX_ITERATIONS:
        return "end"
    return "revise"


# ---- Graph wiring -----------------------------------------------------

def build_graph():
    g = StateGraph(AgentState)
    g.add_node("attach_schema", _attach_schema)
    g.add_node("generate_sql", generate_sql_node)
    g.add_node("execute", execute_node)
    g.add_node("verify", verify_node)
    g.add_node("revise", revise_node)

    g.add_edge(START, "attach_schema")
    g.add_edge("attach_schema", "generate_sql")
    g.add_edge("generate_sql", "execute")
    g.add_edge("execute", "verify")
    g.add_conditional_edges(
        "verify",
        route_after_verify,
        {"revise": "revise", "end": END},
    )
    g.add_edge("revise", "execute")
    return g.compile()


graph = build_graph()
