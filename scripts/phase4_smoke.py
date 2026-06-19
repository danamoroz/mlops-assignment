#!/usr/bin/env python3
"""Phase 4 smoke batch — fire eval questions through the agent with Langfuse tags.

Run (agent + vLLM must be up):
    uv run python scripts/phase4_smoke.py
    uv run python scripts/phase4_smoke.py --count 10 --batch-id local-smoke-test
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVAL_SET = ROOT / "evals" / "eval_set.jsonl"
DEFAULT_AGENT = "http://localhost:8001/answer"


def post_answer(url: str, question: str, db_id: str, tags: dict[str, str]) -> dict:
    payload = json.dumps({
        "question": question,
        "db": db_id,
        "tags": tags,
    }).encode()
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        return json.loads(resp.read())


def main() -> None:
    p = argparse.ArgumentParser(description="Phase 4 Langfuse smoke batch")
    p.add_argument("--count", type=int, default=10, help="number of eval questions")
    p.add_argument("--agent-url", default=DEFAULT_AGENT)
    p.add_argument(
        "--batch-id",
        default=f"local-smoke-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M')}",
    )
    p.add_argument("--eval-set", type=Path, default=EVAL_SET)
    p.add_argument("--source", default="phase4_batch")
    args = p.parse_args()

    if not args.eval_set.exists():
        raise SystemExit(f"eval set not found: {args.eval_set}")

    lines = [
        line for line in args.eval_set.read_text().splitlines() if line.strip()
    ][: args.count]
    if not lines:
        raise SystemExit(f"no questions in {args.eval_set}")

    health_url = args.agent_url.replace("/answer", "/health")
    try:
        with urllib.request.urlopen(health_url, timeout=5) as resp:
            health = json.loads(resp.read())
    except urllib.error.URLError as e:
        raise SystemExit(f"agent not reachable at {health_url}: {e}") from e

    if not health.get("langfuse_enabled"):
        print("warning: agent reports langfuse_enabled=false — set LANGFUSE_* in .env and restart", file=sys.stderr)

    results: list[dict] = []
    revise_count = 0

    for i, line in enumerate(lines, start=1):
        item = json.loads(line)
        db_id = item["db_id"]
        tags = {
            "run_type": "smoke",
            "source": args.source,
            "db_id": db_id,
            "batch_id": args.batch_id,
            "seq": str(i),
        }
        print(f"[{i}/{len(lines)}] {db_id} …", flush=True)
        try:
            out = post_answer(args.agent_url, item["question"], db_id, tags)
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            raise SystemExit(f"HTTP {e.code} on question {i}: {body}") from e

        iterations = out.get("iterations", 0)
        if iterations >= 2:
            revise_count += 1
        results.append({
            "seq": i,
            "db_id": db_id,
            "ok": out.get("ok"),
            "iterations": iterations,
            "error": out.get("error"),
        })

    print()
    print(json.dumps({
        "batch_id": args.batch_id,
        "total": len(results),
        "ok": sum(1 for r in results if r["ok"]),
        "with_revise": revise_count,
        "langfuse_enabled": health.get("langfuse_enabled"),
        "results": results,
    }, indent=2))
    print(f"\nOpen Langfuse → Tracing, filter batch_id={args.batch_id} (metadata or tag)")
    if revise_count == 0:
        print("note: no revise loops this batch — check formula_1 question manually if needed", file=sys.stderr)


if __name__ == "__main__":
    main()
