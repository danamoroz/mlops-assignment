#!/usr/bin/env python3
"""Fire a few load_test-tagged requests sequentially for Langfuse visibility.

Local Langfuse often drops span batches under concurrent load. Run this
*after* a load test (or instead of tracing during one) to get inspectable
traces with run_type=load_test and a distinct batch_id.

Usage:
    uv run python scripts/phase6_trace_sample.py
    uv run python scripts/phase6_trace_sample.py --batch-id nebius-baseline-traces --count 5
"""
from __future__ import annotations

import argparse
import json
import random
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PERF_POOL = ROOT / "load_test" / "perf_pool.jsonl"
DEFAULT_AGENT = "http://localhost:8001/answer"


def post_answer(url: str, question: str, db_id: str, tags: dict[str, str], timeout: float) -> dict:
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
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def main() -> None:
    p = argparse.ArgumentParser(description="Sequential load_test traces for Langfuse")
    p.add_argument("--agent-url", default=DEFAULT_AGENT)
    p.add_argument("--batch-id", default=f"load-trace-sample-{int(time.time())}")
    p.add_argument("--config-label", default="nebius-30b-baseline")
    p.add_argument("--count", type=int, default=5, help="number of sequential requests")
    p.add_argument("--timeout", type=float, default=180.0)
    args = p.parse_args()

    if not PERF_POOL.exists():
        sys.exit(f"{PERF_POOL} not found — run scripts/load_data.py first")

    questions = [json.loads(line) for line in PERF_POOL.read_text().splitlines() if line.strip()]
    rnd = random.Random(0)
    picked = [rnd.choice(questions) for _ in range(args.count)]

    print(f"Sending {args.count} sequential load_test requests → Langfuse")
    print(f"  batch_id={args.batch_id}")
    print(f"  config_label={args.config_label}")
    print("  Agent must have Langfuse enabled (do NOT set LANGFUSE_DISABLED=1)")
    print()

    for i, q in enumerate(picked, 1):
        tags = {
            "run_type": "load_test",
            "source": "trace_sample",
            "db_id": q["db_id"],
            "batch_id": args.batch_id,
            "config_label": args.config_label,
            "seq": str(i),
        }
        t0 = time.monotonic()
        try:
            body = post_answer(args.agent_url, q["question"], q["db_id"], tags, args.timeout)
            elapsed = time.monotonic() - t0
            print(f"[{i}/{args.count}] ok={body.get('ok')} iter={body.get('iterations')} "
                  f"latency={elapsed:.1f}s db={q['db_id']}")
        except urllib.error.HTTPError as e:
            elapsed = time.monotonic() - t0
            print(f"[{i}/{args.count}] HTTP {e.code} latency={elapsed:.1f}s db={q['db_id']}")
        except Exception as e:  # noqa: BLE001
            elapsed = time.monotonic() - t0
            print(f"[{i}/{args.count}] {type(e).__name__}: {e} latency={elapsed:.1f}s")

    print()
    print("Wait ~30s, then open Langfuse → Tracing:")
    print(f"  filter metadata: run_type = load_test")
    print(f"  filter metadata: batch_id = {args.batch_id}")
    print("  (or search batch_id in the trace list search box)")


if __name__ == "__main__":
    main()
