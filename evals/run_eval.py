"""Eval runner using execution accuracy.

Reads evals/eval_set.jsonl, calls the agent at AGENT_URL on each question,
then compares the agent's SQL output to the gold SQL by *executed rows*
(canonicalized: sorted, stringified, None-coerced to empty).

Helpers (run_sql / canonicalize / matches) are provided. You implement
eval_one() and summarize().

Run:
    uv run python evals/run_eval.py --out results/eval_baseline.json
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import time
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EVAL_FILE = ROOT / "evals" / "eval_set.jsonl"
DEFAULT_OUT_FILE = ROOT / "results" / "eval_baseline.json"
DB_DIR = ROOT / "data" / "bird"
AGENT_URL_DEFAULT = "http://localhost:8001/answer"
MAX_EVAL_ITERATIONS = 3
AGENT_TIMEOUT = 300.0


# ---------- Helpers (provided) -----------------------------------------

def run_sql(db_id: str, sql: str, timeout: float = 5.0) -> tuple[bool, list[tuple] | None, str | None]:
    """Run sql against db_id in read-only mode. Returns (ok, rows, error)."""
    path = DB_DIR / f"{db_id}.sqlite"
    try:
        with sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=timeout) as conn:
            cur = conn.execute(sql)
            rows = cur.fetchall()
            return True, rows, None
    except Exception as e:  # noqa: BLE001
        return False, None, f"{type(e).__name__}: {e}"


def canonicalize(rows: list[tuple] | None) -> list[tuple] | None:
    """Sort rows; coerce cells to str; None -> ''."""
    if rows is None:
        return None
    return sorted(tuple("" if c is None else str(c) for c in row) for row in rows)


def matches(gold_rows: list[tuple] | None, pred_rows: list[tuple] | None) -> bool:
    if gold_rows is None or pred_rows is None:
        return False
    return canonicalize(gold_rows) == canonicalize(pred_rows)


# ---------- Phase 5 implementation -------------------------------------

def _extract_sql_attempts(history: list[dict]) -> list[str]:
    attempts: list[str] = []
    for entry in history:
        if entry.get("node") in ("generate_sql", "revise") and entry.get("sql"):
            attempts.append(entry["sql"])
    return attempts


def _pad_attempts(attempts: list[str], n: int = MAX_EVAL_ITERATIONS) -> list[str]:
    """Carry-forward: repeat the last SQL when the agent stopped early."""
    if not attempts:
        return [""] * n
    out = list(attempts[:n])
    while len(out) < n:
        out.append(out[-1])
    return out


def _score_sql(db_id: str, gold_rows: list[tuple], sql: str) -> bool:
    if not sql.strip():
        return False
    ok, pred_rows, _ = run_sql(db_id, sql)
    if not ok or pred_rows is None:
        return False
    return matches(gold_rows, pred_rows)


def _failed_result(
    question: dict,
    *,
    agent_error: str,
    gold_sql: str = "",
) -> dict:
    return {
        "db_id": question["db_id"],
        "question": question["question"],
        "gold_sql": gold_sql or question.get("gold_sql", ""),
        "agent_sql": "",
        "agent_ok": False,
        "agent_iterations": 0,
        "agent_error": agent_error,
        "final_correct": False,
        "correct_by_iteration": [False] * MAX_EVAL_ITERATIONS,
        "sql_by_iteration": [""] * MAX_EVAL_ITERATIONS,
    }


def eval_one(question: dict, agent_url: str) -> dict:
    """Score one question. Return a dict capturing per-iteration correctness."""
    db_id = question["db_id"]
    qtext = question["question"]
    gold_sql = question["gold_sql"]

    gold_ok, gold_rows, gold_err = run_sql(db_id, gold_sql)
    if not gold_ok or gold_rows is None:
        return _failed_result(
            question,
            agent_error=f"gold SQL failed: {gold_err}",
            gold_sql=gold_sql,
        )

    payload = {
        "question": qtext,
        "db": db_id,
        "tags": {
            "run_type": "eval",
            "source": "run_eval",
            "batch_id": "eval_baseline",
            "db_id": db_id,
        },
    }

    try:
        with httpx.Client(timeout=AGENT_TIMEOUT) as client:
            resp = client.post(agent_url, json=payload)
            resp.raise_for_status()
            body = resp.json()
    except httpx.HTTPError as e:
        return _failed_result(question, agent_error=f"agent request failed: {e}")

    history = body.get("history") or []
    agent_sql = str(body.get("sql") or "")
    sql_by_iteration = _pad_attempts(_extract_sql_attempts(history))
    correct_by_iteration = [
        _score_sql(db_id, gold_rows, sql) for sql in sql_by_iteration
    ]
    final_correct = _score_sql(db_id, gold_rows, agent_sql)

    return {
        "db_id": db_id,
        "question": qtext,
        "gold_sql": gold_sql,
        "agent_sql": agent_sql,
        "agent_ok": bool(body.get("ok")),
        "agent_iterations": int(body.get("iterations") or 0),
        "agent_error": body.get("error"),
        "final_correct": final_correct,
        "correct_by_iteration": correct_by_iteration,
        "sql_by_iteration": sql_by_iteration,
    }


def summarize(results: list[dict]) -> dict:
    """Aggregate per-question results.

    Per-iteration carry-forward: if the agent terminated at iteration j < k
    (verify said ok at j, or it hit MAX_ITERATIONS at j < k), treat the
    question's iteration-k result as identical to its iteration-j result.
    The agent stopped emitting; whatever it had at termination is what
    would have been served had we polled at iteration k.
    """
    total = len(results)
    if total == 0:
        return {
            "total": 0,
            "final_pass_rate": 0.0,
            "pass_rate_by_iteration": {str(k): 0.0 for k in range(MAX_EVAL_ITERATIONS)},
            "avg_agent_iterations": 0.0,
            "agent_ok_rate": 0.0,
            "iteration_histogram": {},
        }

    iteration_counts: dict[str, int] = {}
    for r in results:
        key = str(r.get("agent_iterations", 0))
        iteration_counts[key] = iteration_counts.get(key, 0) + 1

    return {
        "total": total,
        "final_pass_rate": sum(1 for r in results if r["final_correct"]) / total,
        "pass_rate_by_iteration": {
            str(k): sum(r["correct_by_iteration"][k] for r in results) / total
            for k in range(MAX_EVAL_ITERATIONS)
        },
        "avg_agent_iterations": sum(r["agent_iterations"] for r in results) / total,
        "agent_ok_rate": sum(1 for r in results if r.get("agent_ok")) / total,
        "iteration_histogram": iteration_counts,
    }


# ---------- Main (provided) --------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--eval-set", type=Path, default=DEFAULT_EVAL_FILE)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_FILE)
    parser.add_argument("--agent-url", default=AGENT_URL_DEFAULT)
    parser.add_argument("--limit", type=int, default=0, help="max questions (0 = all)")
    args = parser.parse_args()

    questions = [json.loads(line) for line in args.eval_set.read_text().splitlines() if line.strip()]
    if args.limit > 0:
        questions = questions[: args.limit]
    print(f"Loaded {len(questions)} eval questions from {args.eval_set}")

    results: list[dict] = []
    t0 = time.monotonic()
    for i, q in enumerate(questions, 1):
        print(f"[{i}/{len(questions)}] {q['db_id']}: {q['question'][:60]}...", flush=True)
        results.append(eval_one(q, args.agent_url))
    elapsed = time.monotonic() - t0

    summary = summarize(results)
    out = {
        "summary": summary,
        "wall_clock_seconds": elapsed,
        "results": results,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, indent=2))
    print(f"Wrote {args.out}")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
