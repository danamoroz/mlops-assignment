# Phase 5 Plan — Nebius H100 VM (Final / Submission Environment)

This plan adapts [README.md Phase 5 (Evals)](../README.md#phase-5-evals) for the **Nebius H100 slot**. It builds on what we already validated locally in [`_local_dev/phase_5_plan.md`](_local_dev/phase_5_plan.md). Local Phase 5 implementation is done in `evals/run_eval.py` (`eval_one`, `summarize`, Langfuse tags); this session **re-runs the full 30-question baseline on 30B**, captures the Grafana submission screenshot, and records the loop verdict for `REPORT.md`.

Per [assignment_remarks.md](_local_dev/assignment_remarks.md): implement and debug the eval harness locally first; **submission artifacts** (`results/eval_baseline.json`, `screenshots/grafana_eval_run.png`, pass rates in `REPORT.md`) must come from **H100 + Qwen3-30B** ([screenshots/CAPTURE.md](../screenshots/CAPTURE.md)).

---

## Goal

By the end of Phase 5 on Nebius you should have:

- **`evals/run_eval.py`** completing end-to-end on all **30** questions against **`Qwen/Qwen3-30B-A3B-Instruct-2507`**
- **`results/eval_baseline.json`** with **overall pass rate**, **`pass_rate_by_iteration`** (`"0"`, `"1"`, `"2"`), and per-question detail
- A written **loop verdict**: does iter-2 pass rate beat iter-0 meaningfully, or is the verify→revise loop a no-op?
- **`screenshots/grafana_eval_run.png`** — Serving dashboard reacting while the 30-question batch hits vLLM
- Optional scratch log: H100 30B numbers vs local/practice baseline (for Phase 6 / `REPORT.md`)

**Out of scope for Phase 5** (later phases): SLO load test at 10 RPS × 5 min (Phase 6), post-tuning `eval_after_tuning.json` (Phase 6/7), final `REPORT.md` prose polish (Phase 7). Phase 5 only needs baseline eval numbers + Grafana screenshot on 30B.

---

## What you are building (context)

Phase 5 is an **execution-accuracy benchmark**, not string matching on SQL text. Two syntactically different queries that return the same row set on the same DB count as correct.

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

### Per-iteration pass rate (the loop question)

README asks: *if we had stopped after iter 0, what would pass rate be? After iter 1? Iter 2?*

With `MAX_ITERATIONS = 3` in `agent/graph.py`, there are at most **3** SQL-producing calls (1× generate + up to 2× revise). Report pass rates for **k ∈ {0, 1, 2}**.

| Eval iter k | SQL source in `history` | Agent graph event |
|-------------|-------------------------|-------------------|
| 0 | First `generate_sql` entry | Initial generate → execute → verify |
| 1 | First `revise` entry (if any) | First revise → execute → verify |
| 2 | Second `revise` entry (if any) | Second revise → execute → verify |

**Carry-forward rule:** if the agent terminates at attempt j < k (verifier accepted at j, or hit `MAX_ITERATIONS`), the SQL at k is the same as at j — the agent stopped emitting new queries.

**Loop verdict you need:**

- Compare **`pass_rate_by_iteration["0"]`** vs **`pass_rate_by_iteration["2"]`**
- If iter 0 ≈ iter 2 → loop is not helping (or verify is a pass-through)
- If iter 2 meaningfully higher → revise loop earns its keep
- Also note **`final_pass_rate`** vs **`agent_ok_rate`**: verifier acceptance ≠ execution accuracy

---

## What we already have locally (don't re-invent)

Validated on WSL2 / laptop (2026-06), per [`phase_5_plan.md`](_local_dev/phase_5_plan.md):

| Item | Local status | On Nebius |
|------|--------------|-----------|
| `eval_one()` | `evals/run_eval.py` — HTTP, gold + per-iter scoring, carry-forward | **No code changes** — run as-is |
| `summarize()` | Overall + `pass_rate_by_iteration`, histogram, `agent_ok_rate` | Same |
| Langfuse tags on eval | `run_type=eval`, `source=run_eval`, `batch_id=eval_baseline`, `db_id` | Traces land in **VM** Langfuse (`config_label=h100-30b` auto) |
| CLI | `--out`, `--limit`, `--agent-url`, `--eval-set` | Use defaults for submission |
| Helpers | `run_sql`, `canonicalize`, `matches` | Read-only SQLite under `data/bird/` |
| Smoke pattern | `scripts/phase4_smoke.py` tag schema | Eval uses same keys (Phase 4 locked schema) |
| Practice baseline | Nebius API / local stand-in — ~40% flat per-iter | **Replace** with H100 self-hosted numbers |

**Do not re-implement the eval harness on H100.** `evals/run_eval.py` is complete. Do not change `agent/graph.py`, `agent/server.py`, or `eval_set.jsonl` unless the agent API is broken on 30B.

**Do not cite practice pass rates in submission.** `REPORT.md` placeholders expect H100 self-hosted vLLM numbers only.

---

## Local vs Nebius (what changes)

| Local test (WSL / 0.6B or Path A API) | Nebius H100 VM |
|----------------------------------------|----------------|
| Harness + per-iter scoring validated | Same runner; **30B** agent quality |
| Directional pass rates (may be low / flat) | **Submission** `eval_baseline.json` |
| Grafana flat on Path A (no local vLLM metrics) | **Required** `grafana_eval_run.png` — panels must move |
| Langfuse at WSL `localhost:3001` | Langfuse at **VM** `localhost:3001` — filter `batch_id=eval_baseline` |
| Practice numbers in notes | Numbers for `REPORT.md` § Baseline evaluation |

Phase 5 on H100 is mostly **run + screenshot + analyze**. Expect **~60–90+ vLLM calls** (generate + verify per iteration; revise adds more) over **~30–60 minutes** wall clock.

---

## Prerequisites (Nebius VM)

Confirm before starting Phase 5 (most come from [Phase 0](final_phase_0.md)–[Phase 4](final_phase_4.md)):

- [ ] **Phase 0 complete** — `data/bird/` loaded, Grafana at http://localhost:3000 (port forward **3000**)
- [ ] **Phase 1 complete** — 30B vLLM healthy on `:8000`, Prometheus scraping `/metrics`
- [ ] **Phase 3 complete** — agent on `:8001`, revise loop proven on 30B ([`phase3_h100_scratch_log.md`](phase3_h100_scratch_log.md))
- [ ] **Phase 4 complete** — Langfuse tracing on VM, tag schema locked ([`phase4_h100_scratch_log.md`](phase4_h100_scratch_log.md))
- [ ] **`.env`** — `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, no Path A `VLLM_BASE_URL` override
- [ ] **Eval set present** — `evals/eval_set.jsonl` (30 lines)

Quick preflight:

```bash
cd ~/mlops-assignment
docker compose ps | grep -E 'grafana|prometheus|vllm'
curl -sf http://localhost:8000/health && echo "vLLM ok"
curl -sf http://localhost:8001/health | jq .
test -f evals/eval_set.jsonl && wc -l evals/eval_set.jsonl
curl -sf http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="vllm") | .health'
```

Or use the Phase 7 helper preflight (does not run eval):

```bash
bash scripts/run_phase7_h100.sh preflight
```

Expect agent health:

```json
{"status": "ok", "langfuse_enabled": true}
```

**Not required for Phase 5 acceptance:** Langfuse screenshots (already captured in Phase 4), load-test SLO pass (Phase 6).

---

## Execution steps

### Step 0 — Confirm stack is warm

Same terminal layout as Phases 3–4:

```bash
# Terminal 1 — if not already running
docker compose up -d
bash scripts/start_vllm.sh

# Terminal 2 — agent (restart if .env changed)
set -a && source .env && set +a
export VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

Optional one-question smoke before the full run (~1–2 min):

```bash
uv run python evals/run_eval.py --out results/eval_smoke.json --limit 1
jq '.results[0] | {db_id, final_correct, correct_by_iteration, agent_iterations}' results/eval_smoke.json
```

Confirm `correct_by_iteration` is length 3 and `history`-derived SQL attempts look sane.

---

### Step 1 — Open Grafana before the baseline run

1. http://localhost:3000 (admin / admin) via SSH port forward **3000**
2. Open the **Serving** dashboard (`infra/grafana/provisioning/dashboards/serving.json`)
3. Set time range to **Last 15 minutes**, refresh **5s**
4. Arrange panels so these are visible in one viewport (for the screenshot):
   - **Latency:** TTFT, E2E p95
   - **Throughput:** requests/s or success/s, generation tok/s
   - **KV cache:** `gpu_cache_usage_perc` (or equivalent headroom panel)

Keep this tab open — you will capture during Step 3.

---

### Step 2 — Optional: Langfuse filter ready

Open http://localhost:3001 → **Tracing**. After the eval, filter by:

- `batch_id` = `eval_baseline`
- `run_type` = `eval`
- `config_label` = `h100-30b`

Useful for debugging questions where `final_correct` is false — not a submission requirement.

---

### Step 3 — Run baseline eval (30 questions)

**Start the Grafana screenshot timer when you launch this.**

```bash
cd ~/mlops-assignment
uv run python evals/run_eval.py --out results/eval_baseline.json
```

Or via the Phase 7 wrapper (same command, prints summary after):

```bash
bash scripts/run_phase7_h100.sh eval-baseline
```

Expect:

- **30 sequential agent HTTP calls** (one per question; runner is not concurrent)
- **~60–90+ vLLM calls** total (2 LLM nodes per iteration × 1–3 iterations)
- **~30–60 minutes** wall clock on H100 (depends on revise rate and cold start)
- Progress lines: `[i/30] db_id: question...`
- Output includes `wall_clock_seconds` in the JSON root

**While it runs:** watch Grafana — request rate, latency, and KV panels should react. Capture **`screenshots/grafana_eval_run.png`** mid-run or immediately after while the time window still shows the spike.

Do **not** kill early unless a question hangs beyond the 300s httpx timeout — that indicates vLLM/agent failure, not normal slowness.

---

### Step 4 — Capture submission screenshot

Per [screenshots/CAPTURE.md](../screenshots/CAPTURE.md):

| File | What to capture |
|------|-----------------|
| `screenshots/grafana_eval_run.png` | Full **Serving** dashboard during or right after the 30-question eval — panels visibly reacting (not flat idle lines) |

Tips:

- Capture from the **laptop browser** via port forward `:3000`
- If panels already rolled off the default window, set time range to cover the eval start/end
- Include enough of the dashboard that latency + throughput + KV rows are readable
- Path A / local practice captures do **not** count — vLLM metrics must come from H100 self-hosted `:8000`

---

### Step 5 — Read results and write loop verdict

Inspect summary:

```bash
jq '.summary' results/eval_baseline.json
```

Record in [`phase5_h100_scratch_log.md`](phase5_h100_scratch_log.md) (create) and later `REPORT.md`:

| Metric | H100 value | Interpretation |
|--------|------------|----------------|
| `final_pass_rate` | ? | Overall execution accuracy |
| `pass_rate_by_iteration["0"]` | ? | First-attempt quality |
| `pass_rate_by_iteration["1"]` | ? | After first revise (if any) |
| `pass_rate_by_iteration["2"]` | ? | After full loop budget |
| Δ iter2 − iter0 | ? | Loop lift (or lack thereof) |
| `avg_agent_iterations` | ? | How often revise fires |
| `agent_ok_rate` | ? | Verifier acceptance (compare to execution accuracy) |
| `iteration_histogram` | ? | Distribution of `agent_iterations` |

**Loop is doing real work if:** iter-2 pass rate > iter-0 by a meaningful margin (even a few points on n=30), and `iteration_histogram` shows multiple questions with `iterations >= 2`.

**Loop is a no-op if:** pass rates flat across iterations *and* most runs terminate at iter 1 with high `agent_ok_rate` — verifier passes first SQL regardless of row-set correctness, or revise does not change SQL meaningfully.

Dig into failures:

```bash
jq '[.results[] | select(.final_correct | not) | {db_id, question: .question[:60], agent_iterations, correct_by_iteration, agent_ok}]' results/eval_baseline.json
```

Find revise successes (iter 0 wrong, iter 1+ correct):

```bash
jq '[.results[] | select(.correct_by_iteration[0] == false and .final_correct == true) | {db_id, question: .question[:60], correct_by_iteration}]' results/eval_baseline.json
```

Cross-reference one failure in Langfuse (`batch_id=eval_baseline`) if traces help explain verifier vs execution mismatch.

---

### Step 6 — Stage submission artifacts

`results/*.json` is gitignored — force-add the baseline for submission:

```bash
git add -f results/eval_baseline.json
git add screenshots/grafana_eval_run.png
git status
```

Update `REPORT.md` § Baseline evaluation with H100 numbers (full prose polish can wait for Phase 7, but replace `*(fill on H100)*` placeholders now so numbers are not lost).

---

## Phase 5 completion checklist

### H100 / submission (this session)

- [ ] vLLM + agent running on 30B; preflight passes
- [ ] Grafana Serving dashboard open with 5s refresh before eval
- [ ] `uv run python evals/run_eval.py --out results/eval_baseline.json` completes all 30 questions
- [ ] `results/eval_baseline.json` has `summary.final_pass_rate` and `summary.pass_rate_by_iteration` keys `"0"`, `"1"`, `"2"`
- [ ] `screenshots/grafana_eval_run.png` captured during H100 eval (panels reacting)
- [ ] Loop verdict written (iter 0 vs iter 2, `agent_ok_rate` vs execution accuracy)
- [ ] Optional: Langfuse traces for `batch_id=eval_baseline` visible on VM
- [ ] `git add -f results/eval_baseline.json` staged for commit

### Already done locally (reference only)

- [x] `eval_one()` — HTTP call, gold + pred execution, per-iter scoring with carry-forward
- [x] `summarize()` — overall + `pass_rate_by_iteration`, histogram, `agent_ok_rate`
- [x] Langfuse tags on eval requests (`run_type=eval`, `batch_id=eval_baseline`)
- [x] `--limit` flag for smoke runs
- [x] Practice baseline run (directional numbers — not for submission)

---

## Troubleshooting (H100)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Connection refused` on agent | Agent not running | Start uvicorn on `:8001` |
| HTTP 500 on `/answer` | vLLM down / bad `.env` | Check `VLLM_BASE_URL`; read agent logs |
| Eval hangs on one question | vLLM OOM or 300s timeout | Check vLLM logs; `nvidia-smi`; restart vLLM; re-run with `--limit` to skip past completed indices manually if needed |
| All `correct_by_iteration` identical | Carry-forward bug or loop never revises | Inspect one multi-iter response: `jq '.history'` on a manual `/answer`; confirm revise nodes in history |
| High `agent_ok_rate`, low `final_pass_rate` | Verifier too lenient | Expected on some configs — note for Phase 3/6 tuning; eval uses execution accuracy |
| Gold SQL fails in `run_sql` | Missing DB file | `uv run python scripts/load_data.py`; check `data/bird/{db_id}.sqlite` |
| Grafana flat during eval | Wrong dashboard / vLLM metrics not scraped | Confirm Prometheus `vllm` target UP; eval hits `:8000` via agent, not Path A |
| Pass rate much lower than Phase 4 smoke `ok` rate | `ok` is verifier label, not execution accuracy | Normal — Phase 5 ground truth is row-set match |
| `results/eval_baseline.json` not in `git status` | Gitignore | `git add -f results/eval_baseline.json` |
| Langfuse empty for eval | Keys off or wrong instance | VM `:3001` only; filter `batch_id=eval_baseline` after run completes |

During eval, **do not** run concurrent load tests — keep vLLM dedicated to the sequential eval batch for clean Grafana signal and stable latencies.

---

## File touch map

| File | Action |
|------|--------|
| `evals/run_eval.py` | **No changes expected** — already implemented |
| `evals/eval_set.jsonl` | Read-only — 30 gold questions |
| `results/eval_baseline.json` | **Output** — written by runner; `git add -f` for submission |
| `screenshots/grafana_eval_run.png` | **Capture this session** |
| `agent/server.py` | No changes expected |
| `agent/graph.py` | No changes expected (tune `MAX_ITERATIONS` in Phase 6 if eval data warrants) |
| `_notes/phase5_h100_scratch_log.md` | **Create** — H100 numbers + loop verdict |
| `REPORT.md` | Replace H100 placeholders in § Baseline evaluation (full polish Phase 7) |

---

## What to defer (but plan for)

| Item | When |
|------|------|
| `results/eval_after_tuning.json` | Phase 6 — after one vLLM tuning knob |
| SLO load test + `grafana_serving.png` | Phase 6 |
| Agent prompt / `MAX_ITERATIONS` changes driven by eval | Phase 6 — measure eval impact after each knob |
| Full `REPORT.md` agent-value paragraph | Phase 7 |
| Re-run baseline after major prompt change | Optional — only if you change agent logic before submission |

---

## Relationship to later phases

| Phase | Dependency on Phase 5 |
|-------|------------------------|
| **6 (SLOs)** | Baseline eval establishes quality floor; post-tuning eval compares `eval_baseline.json` vs `eval_after_tuning.json`. Same Grafana stack — eval run is lighter load than 10 RPS × 5 min. |
| **7 (REPORT)** | **15% eval rigor** — execution-accuracy methodology, overall + per-iteration pass rates, honest loop assessment, `grafana_eval_run.png` reference. |
| **Agent tuning** | If iter 0 ≈ iter 2, consider harder verify prompt or higher `MAX_ITERATIONS`; if revise never fires, check verify strictness. |

Phase 4 tags (`run_type=eval`, `batch_id=eval_baseline`) let you cross-reference Langfuse traces for questions where `final_correct` is false.

---

## Time budget (single H100 session)

| Block | Duration | Notes |
|-------|----------|-------|
| Preflight + Grafana setup | 5–10 min | Confirm vLLM/agent; open Serving dashboard |
| Optional 1-question smoke | 2–3 min | `--limit 1` |
| Full baseline eval (30 Q) | 30–60 min | Sequential; ~1–2 min/question with revise |
| Grafana screenshot | 2–5 min | During or immediately after eval |
| Results analysis + scratch log | 10–15 min | Summary jq, failure samples, loop verdict |
| **Total** | **~50–90 min** | Assumes Phases 1–4 stack already up |

If slot time is tight, run Phase 5 **immediately after Phase 4** while vLLM and agent are still warm — same terminals, no cold-start penalty.

---

## Next phase

**Phase 6 (SLOs)** — run `load_test/driver.py` against the platform SLO (P95 < 5s, 10+ RPS over 5 minutes), compare Grafana before/after one tuning knob, capture `grafana_before.png` / `grafana_after.png`, then `eval_after_tuning.json`. See [README Phase 6](../README.md#phase-6-slos) and [`_local_dev/phase_6_plan.md`](_local_dev/phase_6_plan.md).
