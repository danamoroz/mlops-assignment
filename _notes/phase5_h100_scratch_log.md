# Phase 5 H100 scratch log

Run date: 2026-06-19  
Model: `Qwen/Qwen3-30B-A3B-Instruct-2507` (self-hosted vLLM on `:8000`)  
Command: `uv run python evals/run_eval.py --out results/eval_baseline.json`  
Wall clock: **45.6 s** (30 questions, sequential)

## Preflight

- [x] vLLM on `:8000` — 30B model id confirmed
- [x] Agent on `:8001` — `langfuse_enabled: true`
- [x] Prometheus `vllm` target UP
- [x] Grafana stack running (`docker compose up -d`)
- [x] 1-question smoke (`eval_smoke.json`) — revise loop OK on `formula_1`

## Summary

| Metric | H100 value | Interpretation |
|--------|------------|----------------|
| `final_pass_rate` | **43.3%** (13/30) | Overall execution accuracy |
| `pass_rate_by_iteration["0"]` | **40.0%** | First-attempt quality |
| `pass_rate_by_iteration["1"]` | **43.3%** | After first revise |
| `pass_rate_by_iteration["2"]` | **43.3%** | After full loop budget |
| Δ iter2 − iter0 | **+3.3 pp** | Small loop lift; iter 1 = iter 2 |
| `avg_agent_iterations` | **1.67** | Mix of 1-round and 3-round runs |
| `agent_ok_rate` | **76.7%** | Verifier accepts more than execution accuracy |
| `iteration_histogram` | 1→19, 2→2, 3→9 | Revise fires on 11/30; most stop at iter 1 |

## Loop verdict

**The loop does a little work, but not much.** Iter-0 pass rate is 40%; iter-2 is 43.3% (+3.3 pp on n=30). All lift appears at the first revise — iter 1 and iter 2 are identical (carry-forward on early accept or cap).

Only **one** question flipped from wrong→correct via revise: `formula_1` Australian GP coordinates (iter 0 missed `DISTINCT`; iter 1 fixed). Nine questions ran all 3 iterations without improving row-set correctness.

**Verifier vs execution:** `agent_ok_rate` 76.7% vs `final_pass_rate` 43.3% — verifier accepts SQL that returns wrong row sets on 10+ questions (e.g. `formula_1` Lewis Hamilton lap time: `agent_ok: true`, all iterations wrong).

## Revise success (1)

| `db_id` | Question (truncated) | `correct_by_iteration` | `agent_iterations` |
|---------|----------------------|------------------------|--------------------|
| formula_1 | Australian GP circuit coordinates | [false, true, true] | 2 |

## Notable failures (17 total)

| Pattern | Examples |
|---------|----------|
| Verifier accepted, rows wrong | `formula_1` Lewis Hamilton lap time; `california_schools` lowest-excellence address |
| 3 rounds, never fixed | `financial` district crimes; `toxicology` carcinogen %; `student_club` full names |
| 1 round, wrong, verifier OK | `thrombosis_prediction` Ig G count; `superhero` missing-weight diff |

Full failure list: `jq '[.results[] | select(.final_correct | not)]' results/eval_baseline.json`

## Langfuse

Filter after run: `batch_id=eval_baseline`, `run_type=eval`, `config_label=h100-30b`

## Submission artifacts

- [x] `results/eval_baseline.json`
- [x] `screenshots/grafana_eval_run.png` — Last 15 minutes, Serving dashboard during eval burst

## Next

- Phase 6: load test + tuning; compare `eval_after_tuning.json` to this baseline
