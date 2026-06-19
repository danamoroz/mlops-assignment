# Phase 5 Plan — Local Test Environment

This plan adapts [README.md Phase 5 (Evals)](../README.md#phase-5-evals) for **local development on your machine** (WSL2 / laptop), not the cloud H100 VM. Per [assignment_remarks.md](assignment_remarks.md): implement and validate the eval harness locally first; **submission artifacts** (`results/eval_baseline.json` numbers for `REPORT.md`, `screenshots/grafana_eval_run.png`) should come from the H100 + 30B run later.

---

## Goal

By the end of Phase 5 **locally** you should have:

- `evals/run_eval.py` fully implemented (`eval_one` + `summarize`) and runnable end-to-end
- `results/eval_baseline.json` written with **overall pass rate** and **per-iteration pass rates**
- A clear read on whether the verify+revise loop adds value (iter-0 vs final pass rate)
- Grafana open during the eval run so you know what to capture on H100

**Final submission quality** (H100 only):

- Re-run baseline eval against `Qwen/Qwen3-30B-A3B-Instruct-2507` on the VM
- Commit `results/eval_baseline.json` from the 30B run
- Capture `screenshots/grafana_eval_run.png` while the 30-question batch hits vLLM
- Use pass rates and loop analysis in `REPORT.md` (15% of grade: eval rigor)

---

## What you are building (context)

Phase 5 is an **execution-accuracy benchmark**, not string matching on SQL text. Two queries that look different but return the same row set on the same DB count as correct.

```
evals/eval_set.jsonl  (30 questions)
        │
        ▼
  POST /answer  (per question)  ──► agent returns final sql, rows, iterations, history
        │
        ├── run gold_sql on db_id  ──► gold_rows
        ├── run agent SQL(s)       ──► pred_rows  (final + per-iteration)
        │
        ▼
  canonicalize (sort rows, str cells, None → "")
        │
        ▼
  matches(gold_rows, pred_rows)  →  correct / incorrect
        │
        ▼
  summarize()  →  overall + pass_rate_by_iteration
        │
        ▼
  results/eval_baseline.json
```

### Eval signal (from README)

> Run the agent's final SQL and the gold SQL against the target DB, compare result sets after canonicalizing (sort rows, ignore column-name case). Match → correct, no match → incorrect.

The scaffold already implements row comparison via `run_sql`, `canonicalize`, and `matches`. Column-name case is irrelevant because SQLite returns positional tuples, not named columns.

### Per-iteration pass rate (the loop question)

README asks: *if we had stopped after iter 0, what would pass rate be? After iter 1? Iter 2?*

Map eval iteration index **k** to the **k-th SQL attempt** in the agent run:

| Eval iter k | SQL source in `history` | Agent graph event |
|-------------|-------------------------|-------------------|
| 0 | First `generate_sql` entry | Initial generate → execute → verify |
| 1 | First `revise` entry (if any) | First revise → execute → verify |
| 2 | Second `revise` entry (if any) | Second revise → execute → verify |

With `MAX_ITERATIONS = 3` in `agent/graph.py`, there are at most **3** SQL-producing calls (1× generate + up to 2× revise). Report pass rates for **k ∈ {0, 1, 2}**.

**Carry-forward rule** (documented in `summarize()` docstring): if the agent terminates at attempt j < k (verifier accepted at j, or hit `MAX_ITERATIONS`), the SQL at k is the same as at j — the agent stopped emitting new queries. Whatever was live at termination is what would have been served.

Example: verifier accepts on iter 0 → `correct_by_iteration[1]` and `[2]` reuse iter-0 correctness (same SQL, same rows).

---

## Already scaffolded (minimal code changes expected)

| Piece | File | Status |
|-------|------|--------|
| Eval runner skeleton | `evals/run_eval.py` | `main()` loop, CLI, JSON output — **you fill `eval_one` + `summarize`** |
| Eval questions | `evals/eval_set.jsonl` | 30 rows: `question`, `db_id`, `gold_sql` |
| SQL execution helper | `evals/run_eval.py` | `run_sql(db_id, sql)` — read-only SQLite against `data/bird/{db_id}.sqlite` |
| Row comparison | `evals/run_eval.py` | `canonicalize()`, `matches()` |
| Agent HTTP API | `agent/server.py` | `POST /answer` → `{sql, rows, iterations, ok, history, error}` |
| Agent loop cap | `agent/graph.py` | `MAX_ITERATIONS = 3` |
| Smoke-batch pattern | `scripts/phase4_smoke.py` | Reference for HTTP POST + tags (reuse tag schema) |
| Grafana stack | `docker-compose.yml` | http://localhost:3000 — watch vLLM panels during eval |
| Output path | `results/` | Created by runner; gitignore may exclude — check before commit |

**Do not change** `agent/graph.py`, `agent/server.py`, or `eval_set.jsonl` for Phase 5 unless the agent API is broken.

---

## You implement

| Function | Where | Responsibility |
|----------|-------|----------------|
| `eval_one(question, agent_url)` | `evals/run_eval.py` | HTTP call, gold execution, per-iter scoring, per-question result dict |
| `summarize(results)` | `evals/run_eval.py` | Aggregate counts, overall pass rate, `pass_rate_by_iteration` with carry-forward |

### Suggested `eval_one` algorithm

1. **Call agent** — `POST {agent_url}` with body:

   ```json
   {
     "question": "<from eval row>",
     "db": "<db_id>",
     "tags": {
       "run_type": "eval",
       "source": "run_eval",
       "batch_id": "eval_baseline",
       "db_id": "<db_id>"
     }
   }
   ```

   Use `httpx` (already imported) with a generous timeout (e.g. 300s) — local vLLM can be slow per question.

2. **Handle failures** — agent may return `ok: false` (verify rejected, SQL error, HTTP 500). Still score execution accuracy from whatever SQL was produced; `ok` is agent self-report, not the eval label.

3. **Gold rows** — `ok_g, gold_rows, err_g = run_sql(db_id, gold_sql)`. If gold fails, record an error on that question (data/SQL bug — should not happen on the curated set).

4. **Extract per-iteration SQL from `history`**:

   ```python
   sql_attempts: list[str] = []
   for entry in history:
       if entry.get("node") in ("generate_sql", "revise") and entry.get("sql"):
           sql_attempts.append(entry["sql"])
   ```

   Pad to length 3 by repeating the last attempt (carry-forward):

   ```python
   while len(sql_attempts) < 3:
       sql_attempts.append(sql_attempts[-1] if sql_attempts else "")
   ```

5. **Score each attempt k ∈ {0,1,2}** — run `run_sql(db_id, sql_attempts[k])`, then `matches(gold_rows, pred_rows)`.

6. **Final score** — compare gold to agent's **final** `sql` (or last sql_attempt). Should match `correct_by_iteration[termination_index]` when carry-forward is applied correctly.

7. **Return dict** (shape is yours; keep fields useful for debugging):

   ```python
   {
       "db_id": str,
       "question": str,
       "gold_sql": str,
       "agent_sql": str,           # final sql from response
       "agent_ok": bool,           # verifier accepted
       "agent_iterations": int,    # response.iterations
       "agent_error": str | None,
       "final_correct": bool,
       "correct_by_iteration": [bool, bool, bool],  # iter 0, 1, 2
       "sql_by_iteration": [str, str, str],         # optional, helps debug failures
   }
   ```

### Suggested `summarize` algorithm

```python
{
    "total": len(results),
    "final_pass_rate": sum(r["final_correct"] for r in results) / total,
    "pass_rate_by_iteration": {
        "0": mean(r["correct_by_iteration"][0]),
        "1": mean(r["correct_by_iteration"][1]),
        "2": mean(r["correct_by_iteration"][2]),
    },
    "avg_agent_iterations": mean(r["agent_iterations"]),
    "agent_ok_rate": mean(r["agent_ok"]),   # optional: verifier acceptance vs execution accuracy
    "iteration_histogram": {              # optional: {1: n, 2: n, 3: n}
        str(k): count for k in ...
    },
}
```

The README comparison you need for the loop read:

- **`pass_rate_by_iteration["0"]`** vs **`pass_rate_by_iteration["2"]`** (or `"1"` if most runs stop at 2 iterations)
- If iter 0 ≈ iter 2 → loop is not helping (or verify is a no-op pass-through)
- If iter 2 meaningfully higher → revise loop earns its keep

Also note **`final_pass_rate`** vs **`agent_ok_rate`**: verifier can accept wrong SQL or reject correct SQL — execution accuracy is the ground truth for Phase 5.

---

## Local vs H100 (what changes)

| README (VM / H100) | Local test phase |
|---|---|
| 30B model pass rates for `REPORT.md` | Any backend (0.6B vLLM, hosted API) — validates harness + loop mechanics |
| `screenshots/grafana_eval_run.png` submission | Practice capture locally; **re-capture on H100** |
| ~60 vLLM calls (30 × ~2) | Same count; may take longer on CPU/small GPU |
| Numbers in `REPORT.md` | Directional locally; report **30B numbers** only |

Phase 5 is fully doable off-GPU. A low pass rate on a stand-in model is expected — you are proving the **eval pipeline**, not final agent quality.

---

## Prerequisites (local)

Assumes prior local milestones:

- [x] Phase 0 — `data/bird/` loaded, Grafana at http://localhost:3000
- [x] Phase 3 — agent returns sensible `POST /answer` with `history` and `iterations`
- [x] vLLM or hosted API running and reachable from agent (`VLLM_BASE_URL`, `VLLM_MODEL` in `.env`)
- [x] Agent server running: `uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001`
- [ ] Phase 4 optional but recommended — Langfuse tags on eval runs help debug failures

Quick preflight:

```bash
curl -s http://localhost:8001/health | jq .
curl -s http://localhost:8000/v1/models | jq .   # if using local vLLM
docker compose ps | grep -E 'grafana|prometheus'
```

---

## Step-by-step (local)

### Step 1 — Implement `eval_one` and `summarize`

Edit only `evals/run_eval.py`. Replace the two `NotImplementedError` stubs.

Sanity check on one question before the full run:

```bash
cd /home/danar/repos/ai_performance/mlops/hw2_llm_inference_o11y

# Quick manual probe (same as eval will do)
curl -s -X POST http://localhost:8001/answer \
  -H 'Content-Type: application/json' \
  -d '{"question":"List down Ajax'\''s superpowers.","db":"superhero","tags":{"run_type":"eval","batch_id":"eval_smoke","source":"manual"}}' \
  | jq '{ok, iterations, sql, history: [.history[] | {node, sql: .sql // empty}]}'
```

Confirm `history` contains `generate_sql` / `revise` nodes with `sql` fields you can extract.

---

### Step 2 — Dry-run on 2–3 questions

Temporarily limit the loop in `main()` or add a `--limit` flag (optional convenience — not required for submission):

```bash
# If you add --limit 3:
uv run python evals/run_eval.py --out results/eval_smoke.json --limit 3
```

Without `--limit`, cut the question list in a scratch copy or interrupt after a few lines during dev.

Verify:

- JSON output parses
- `correct_by_iteration` arrays are length 3
- At least one question shows different correctness across iterations (proves per-iter scoring works)

---

### Step 3 — Open Grafana before the full baseline

1. http://localhost:3000 (admin / admin)
2. Open the **Serving** dashboard (`infra/grafana/provisioning/dashboards/serving.json`)
3. Set time range to **Last 15 minutes**, refresh **5s**
4. Arrange panels so **request rate**, **latency**, and **KV cache** (if present) are visible

Keep this tab open — you will screenshot during the run (Step 5).

---

### Step 4 — Run baseline eval (30 questions)

```bash
cd /home/danar/repos/ai_performance/mlops/hw2_llm_inference_o11y
uv run python evals/run_eval.py --out results/eval_baseline.json
```

Expect:

- **~30 agent HTTP calls** (one per question)
- **~60–90+ vLLM calls** (generate + verify per iteration; revise adds more)
- **15–45+ minutes** on a small local model — normal; do not kill early
- Progress lines: `[i/30] db_id: question...`

Optional: watch Langfuse (http://localhost:3001) filtered by `batch_id=eval_baseline` for failed traces.

---

### Step 5 — Grafana screenshot

While the eval is running (or immediately after, if panels still show the spike):

- Capture full dashboard with panels reacting to load
- Save locally as `screenshots/grafana_eval_run.png`

**Local:** validates you know what to capture.

**H100 submission:** re-run eval + re-screenshot on the VM with 30B loaded.

---

### Step 6 — Read results and write your loop verdict

Inspect `results/eval_baseline.json`:

```bash
jq '.summary' results/eval_baseline.json
```

Record in your notes (and later `REPORT.md`):

| Metric | Your local value | Interpretation |
|--------|------------------|----------------|
| `final_pass_rate` | ? | Overall execution accuracy |
| `pass_rate_by_iteration["0"]` | ? | First-attempt quality |
| `pass_rate_by_iteration["2"]` | ? | After full loop budget |
| Δ iter2 − iter0 | ? | Loop lift (or lack thereof) |
| `avg_agent_iterations` | ? | How often revise fires |

**Loop is doing real work if:** iter-2 pass rate > iter-0 by a meaningful margin (even a few points on n=30), and `iteration_histogram` shows revise actually running (`iterations >= 2` on multiple questions).

**Loop is a no-op if:** pass rates flat across iterations *and* most runs terminate at iter 0 with `agent_ok: true` — verifier passes first SQL regardless of correctness, or revise does not change SQL meaningfully.

Dig into per-question failures:

```bash
jq '[.results[] | select(.final_correct | not) | {db_id, question: .question[:50], agent_iterations, correct_by_iteration}]' results/eval_baseline.json
```

---

## Phase 5 completion checklist

### Local test phase (now)

- [ ] `eval_one` implemented — HTTP call, gold + pred execution, per-iter scoring
- [ ] `summarize` implemented — overall + `pass_rate_by_iteration` with carry-forward
- [ ] `uv run python evals/run_eval.py` completes on all 30 questions
- [ ] `results/eval_baseline.json` exists with `summary` + `results` arrays
- [ ] Per-iteration pass rates present (`"0"`, `"1"`, `"2"`)
- [ ] Written note: does the loop help? (even if absolute pass rate is low locally)
- [ ] Grafana watched during run; know which panels to screenshot

### H100 / submission (later)

- [ ] `.env` → `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, local vLLM on `:8000`
- [ ] Re-run `uv run python evals/run_eval.py --out results/eval_baseline.json`
- [ ] Commit `results/eval_baseline.json` from 30B run
- [ ] `screenshots/grafana_eval_run.png` from H100 eval run
- [ ] `REPORT.md` cites 30B pass rates and loop analysis (not local stand-in numbers)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `NotImplementedError` | Stubs not filled | Implement `eval_one` + `summarize` |
| `Connection refused` on agent | Agent not running | Start uvicorn on `:8001` |
| HTTP 500 on `/answer` | vLLM down / bad `.env` | Check `VLLM_BASE_URL`; read agent logs |
| Eval hangs | vLLM OOM or very slow | Reduce concurrent load (runner is sequential — check vLLM health); increase httpx timeout |
| All `correct_by_iteration` identical | Carry-forward bug or loop never revises | Inspect `history` on one multi-iter response; confirm revise nodes present |
| High `agent_ok_rate`, low `final_pass_rate` | Verifier too lenient | Expected locally; note for Phase 3/6 tuning — eval uses execution accuracy |
| Gold SQL fails in `run_sql` | Wrong `db_id` or missing DB | `uv run python scripts/load_data.py`; check `data/bird/{db_id}.sqlite` |
| Empty `sql_attempts` | Agent returned no SQL | Record all iterations false; check agent error field |
| Grafana flat during eval | vLLM metrics not scraped | Confirm vLLM exposes `/metrics`; Prometheus target up (Phase 2) |
| Pass rate 0% everywhere | Stand-in model too weak | OK for local harness test; revisit on 30B |

---

## File touch map

| File | Action |
|------|--------|
| `evals/run_eval.py` | **Implement** `eval_one`, `summarize` (only required code change) |
| `evals/eval_set.jsonl` | Read-only — 30 gold questions |
| `results/eval_baseline.json` | **Output** — written by runner |
| `screenshots/grafana_eval_run.png` | Capture during eval (H100 for submission) |
| `agent/server.py` | No changes expected |
| `agent/graph.py` | No changes expected (tune `MAX_ITERATIONS` later based on eval data) |
| `REPORT.md` | Phase 7 — cite 30B eval numbers and loop verdict |

---

## Relationship to later phases

| Phase | Dependency on Phase 5 |
|-------|------------------------|
| **6 (SLOs)** | Eval quality is separate from serving SLOs, but same Grafana/vLLM stack; load test uses `load_test/driver.py`, not `run_eval.py` |
| **7 (REPORT)** | **15% eval rigor** — execution-accuracy methodology, overall + per-iteration pass rates, honest loop assessment |
| **Agent tuning** | If iter 0 ≈ iter 2, consider harder verify prompt or higher `MAX_ITERATIONS`; if revise never fires, check verify strictness |

Phase 4 tags (`run_type=eval`, `batch_id=eval_baseline`) let you cross-reference Langfuse traces for questions where `final_correct` is false.

---

## Next phase

**Phase 6 (SLOs)** — run `load_test/driver.py` against the platform SLO (P95 < 5s, 10+ RPS over 5 minutes), compare Grafana before/after tuning, filter Langfuse slow traces by tags. See [README Phase 6](../README.md#phase-6-slos).
