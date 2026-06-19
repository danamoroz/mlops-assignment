"""Langfuse trace metadata helpers for agent /answer requests.

Maps the Phase 4 tag schema onto LangGraph invoke config so Langfuse shows
filterable tags (langfuse_tags) plus structured metadata on each trace.
"""
from __future__ import annotations

import os
from typing import Any


def default_config_label() -> str:
    """Short label for the active LLM backend (used in Phase 6 comparisons)."""
    model = os.environ.get("VLLM_MODEL", "unknown")
    lowered = model.lower()
    if "0.6b" in lowered:
        return "local-0.6b"
    if "30b" in lowered:
        return "h100-30b"
    return model.rsplit("/", maxsplit=1)[-1][:48]


def merge_tags(user_tags: dict[str, str], *, db_id: str | None = None) -> dict[str, str]:
    """Merge caller tags with server defaults; user values win on conflict."""
    merged: dict[str, str] = {"config_label": default_config_label()}
    if db_id:
        merged["db_id"] = db_id
    merged.update({k: v for k, v in user_tags.items() if v})
    return merged


def build_langfuse_metadata(tags: dict[str, str], *, db_id: str | None = None) -> dict[str, Any]:
    """Build LangGraph metadata dict understood by langfuse.langchain.CallbackHandler."""
    merged = merge_tags(tags, db_id=db_id)
    langfuse_tags = [f"{key}:{value}" for key, value in sorted(merged.items())]
    trace_db = merged.get("db_id", "unknown")
    return {
        **merged,
        "langfuse_tags": langfuse_tags,
        "langfuse_trace_name": f"answer:{trace_db}",
    }


def build_invoke_config(
    user_tags: dict[str, str],
    *,
    db_id: str,
    handler: Any | None,
) -> dict[str, Any]:
    """RunnableConfig for graph.invoke with Langfuse callbacks + trace metadata."""
    return {
        "callbacks": [handler] if handler is not None else [],
        "metadata": build_langfuse_metadata(user_tags, db_id=db_id),
    }


def annotate_trace_outcome(
    handler: Any | None,
    *,
    iterations: int,
    ok: bool,
) -> None:
    """Add post-run tags so iterations / ok show in the Langfuse trace list."""
    if handler is None:
        return
    trace_id = getattr(handler, "last_trace_id", None)
    if not trace_id:
        return

    try:
        from langfuse import get_client

        client = get_client()
        client._create_trace_tags_via_ingestion(  # noqa: SLF001 — SDK ingestion helper
            trace_id=trace_id,
            tags=[f"iterations:{iterations}", f"agent_ok:{str(ok).lower()}"],
        )
        client.flush()
    except Exception:  # noqa: BLE001 — tracing must never fail the HTTP response
        pass
