# Phase 7 Plan — Nebius H100 VM (Final / Submission Environment)

This plan adapts [README.md Phase 7 (Docs)](../README.md#phase-7-docs) for the **Nebius H100 slot**. It builds on what we already validated locally in [`_local_dev/phase_7_plan.md`](_local_dev/phase_7_plan.md). Local Phase 7 produced the `REPORT.md` skeleton, artifact audit, and `run_phase7_h100.sh`; Phases 1–6 on H100 (2026-06-19) produced submission numbers, load-test JSONs, and all eight screenshots. **This session is polish and gate-check only** — no new implementation.

Per [assignment_remarks.md](_local_dev/assignment_remarks.md): draft structure locally first; **submission-quality numbers, screenshots, and the final ≤3-page writeup** come from H100 + 30B only.

---

## Goal

By the end of Phase 7 on Nebius you should have:

- **`REPORT.md` complete** — all five README sections with H100 numbers only in submission body
- **≤3 pages** (~1,200–1,800 words); appendix optional and trimmed or omitted for graders
- **All 11 artifacts** from the Final deliverables table present and verified
- **Honest verdicts** — SLO miss quantified, loop value cited with `pass_rate_by_iteration`, specific next steps tied to metrics
- **No practice leakage** — Path A / 0.6B / Nebius API numbers confined to appendix or removed

**Out of scope for Phase 7:** new tuning iterations, agent/graph changes, dashboard edits, re-running full 300 s loads unless a screenshot or JSON is missing or corrupt.

---

## What Phase 7 is (and is not)

Phase 7 is **documentation and consolidation**, not engineering.

```
Phases 1–6 on H100 (2026-06-19) — DONE
        │
        ├── results/eval_baseline.json          (43.3% pass rate)
        ├── results/eval_after_tuning.json      (43.3%, MAX_ITERATIONS=2)
        ├── results/load_test_h100_*.json       (baseline + 3 iterations + push-past)
        ├── screenshots/*.png                   (all 8 captured)
        ├── scripts/start_vllm.sh               (final: max-num-seqs=64)
        └── infra/grafana/.../serving.json
        │
        ▼
  REPORT.md polish  (≤3 pages)
        │
        ├── 1. Serving configuration + justifications
        ├── 2. Baseline eval + per-iteration pass rates
        ├── 3. SLO baseline, iteration log, final numbers
        ├── 4. Agent value (did the loop help?)
        └── 5. What I'd do with more time (specific)
```

**Grading emphasis** (from README):

| Area | Weight | Phase 7 cares about |
|------|--------|---------------------|
| Report & communication | **15%** | Clear, honest about misses, ≤3 pages, specific follow-ups |
| (Feeds into) SLO diagnosis | 25% | Iteration log quality — already in §3 from Phase 6 |
| (Feeds into) Eval rigor | 15% | Execution-accuracy methodology + loop analysis in §2 and §4 |

A missed SLO with metric-grounded diagnosis beats a hit you cannot explain.

---

## `REPORT.md` required sections

Map README requirements to headings and primary sources:

| # | README requirement | `REPORT.md` heading | Primary sources | H100 status |
|---|-------------------|---------------------|-----------------|-------------|
| 1 | Serving configuration, flags + one-line justification each | `## Serving configuration` | `scripts/start_vllm.sh`, Phase 1 probe notes | **Filled** — table matches final tuned config |
| 2 | Baseline eval, overall + per-iteration pass rate, commentary | `## Baseline evaluation` | `results/eval_baseline.json` | **Filled** — 43.3%, iter 0/1/2 rates, formula_1 / financial examples |
| 3 | SLO baseline vs target, iteration log, final numbers | `## SLO tuning` | `results/load_test_h100_*.json`, before/after PNGs | **Filled** — MISS verdict, 4 iteration lines |
| 4 | Agent value — one paragraph, cite per-iteration pass rate | `## Agent value` | Same eval JSON + Langfuse traces | **Filled** — cites 40% → 43.3% |
| 5 | What you'd do with more time — specific | `## Next steps` | Phase 6 bottlenecks | **Filled** — 5 metric-tied bullets |

**Length:** target ~1,200–1,800 words. Current draft: **~1,908 words** — trim ~100–300 words before submit.

---

## Final deliverables inventory

Audit as of 2026-06-19 H100 session:

| File | What it is | Status |
|------|------------|--------|
| `REPORT.md` | Writeup ≤3 pages | **Draft complete** — needs trim + status header update |
| `infra/grafana/provisioning/dashboards/serving.json` | Grafana dashboard | **Present** |
| `agent/graph.py`, `agent/prompts.py` | Agent implementation | **Present** |
| `evals/run_eval.py` | Eval runner | **Present** |
| `results/eval_baseline.json` | Baseline eval | **H100** — 43.3% (13/30) |
| `results/eval_after_tuning.json` | Post-tuning eval | **H100** — 43.3%, `avg_agent_iterations` 1.37 |
| `screenshots/vllm_manual_query.png` | vLLM + manual SQL query | **Captured** |
| `screenshots/grafana_serving.png` | Full dashboard under load | **Captured** |
| `screenshots/langfuse_trace.png` | verify→revise waterfall | **Captured** |
| `screenshots/langfuse_tags.png` | Trace list with metadata tags | **Captured** |
| `screenshots/grafana_eval_run.png` | Dashboard during baseline eval | **Captured** |
| `screenshots/grafana_before.png` | Before key tuning change | **Captured** |
| `screenshots/grafana_after.png` | After key tuning change | **Captured** |

Verify anytime:

```bash
bash scripts/run_phase7_h100.sh summary
```

---

## What we already have on H100 (Phases 1–6)

From [Phase 1](final_phase_1.md) through [Phase 6](final_phase_6.md) session (2026-06-19):

| Area | H100 outcome |
|------|--------------|
| **Serving** | `scripts/start_vllm.sh` — BF16 30B, `max-num-seqs 64` (tuned from 32), `gpu-memory-utilization 0.92`, prefix caching + chunked prefill |
| **Agent** | `MAX_ITERATIONS=2` (final); baseline eval used `MAX_ITERATIONS=3` |
| **Baseline eval** | 43.3% `final_pass_rate`; iter 0: 40% / iter 1–2: 43.3%; `agent_ok_rate` 76.7% |
| **SLO baseline** | P95 **113.6 s**, ok 30.7%, 1780 timeouts at 10 RPS × 300 s |
| **SLO final** | P95 **83.4 s**, ok 87.1%, 7 timeouts — still **MISS** (target < 5 s) |
| **Tuning log** | 4 iterations: `max-num-seqs` 32→64; `MAX_ITERATIONS` 3→2; 64→96 probe (reverted); 12 RPS push-past |
| **Quality** | Tuning preserved 43.3% pass rate; `avg_agent_iterations` 1.67 → 1.37 |
| **Screenshots** | All 8 PNGs on disk under `screenshots/` |
| **REPORT.md** | All five submission sections drafted with H100 numbers |

**Key numbers to keep consistent** (always `jq`, never hand-type):

```bash
jq '.summary | {final_pass_rate, pass_rate_by_iteration, avg_agent_iterations, agent_ok_rate}' \
  results/eval_baseline.json results/eval_after_tuning.json

jq '.summary | {latency_p95, latency_p50, achieved_rps, ok, total_requests, timeouts}' \
  results/load_test_h100_baseline.json results/load_test_h100_iter2.json
```

| Run | `latency_p95` | ok rate | `timeouts` |
|-----|---------------|---------|------------|
| Baseline (`max-num-seqs=32`, `MAX_ITERATIONS=3`) | 113.6 s | 922/3000 (30.7%) | 1780 |
| Final (`max-num-seqs=64`, `MAX_ITERATIONS=2`) | 83.4 s | 2614/3000 (87.1%) | 7 |

---

## What we already have locally (don't re-invent)

From [`_local_dev/phase_7_plan.md`](_local_dev/phase_7_plan.md) (2026-06):

| Item | Local status | On Nebius |
|------|--------------|-----------|
| `REPORT.md` skeleton | Five sections + appendix | **Already migrated to H100 numbers** |
| `scripts/run_phase7_h100.sh` | Helper for eval/load/trace/summary | **Use `summary` only** unless re-capture needed |
| `screenshots/CAPTURE.md` | Eight-file checklist | **All items satisfied on H100** |
| Path A practice numbers | Appendix draft | **Keep out of submission sections** |
| Agent value paragraph template | Drafted with practice 40% flat curve | **Updated to H100 43.3% / +3.3 pp** |
| Next steps bullets | Tied to Phase 6 hypotheses | **Refined with H100 queue/KV evidence** |

**Do not re-run H100 loads for Phase 7** unless an artifact is missing or a screenshot fails visual review.

---

## Local vs Nebius (what changes)

| Local test phase | Nebius H100 (this plan) |
|------------------|-------------------------|
| Skeleton `REPORT.md` with `<!-- H100 -->` placeholders | **Paste-in done** — polish prose only |
| Practice JSONs (Path A 40% flat) | **Overwritten** with H100 eval results |
| Screenshot inventory + `CAPTURE.md` | **All eight PNGs captured** |
| Appendix with Path A / 0.6B tables | **Trim or delete** before submission |
| `wc -w` check on structure | **Trim ~100–300 words** to hit ≤1,800 |

---

## Prerequisites (Nebius VM)

Phase 7 does **not** require a live stack unless re-capturing screenshots. For polish-only session:

- [x] H100 eval JSONs committed
- [x] H100 load-test JSONs committed
- [x] All eight screenshots on disk
- [x] `REPORT.md` submission sections filled with H100 numbers
- [ ] Word count ≤1,800
- [ ] Status header updated (remove "screenshots missing")
- [ ] Appendix trimmed; no Path A numbers in §1–§5
- [ ] `bash scripts/run_phase7_h100.sh summary` — all OK

Optional re-verify on VM (if paranoia):

```bash
cd ~/mlops-assignment
bash scripts/run_phase7_h100.sh summary
wc -w REPORT.md
grep -E 'Path A|0\.6B|practice|placeholder' REPORT.md
```

---

## Step-by-step (H100 finalization)

Most steps are **already complete**. Run only what remains.

### Step 0 — Artifact audit ✅

```bash
bash scripts/run_phase7_h100.sh summary
```

Expected: all lines `OK`. If any `missing`, see [Re-capture playbook](#re-capture-playbook) below.

---

### Step 1 — Verify `REPORT.md` numbers against JSON ✅ (spot-check)

Cross-check every table in §2–§3 against `jq` output. Common drift points:

- P95 rounded to one decimal (113.6, 83.4) — must match `load_test_*.json`
- Pass rates as percentages (43.3%) — must match `eval_*.json` × 100
- Iteration log `config_label` / file names — `load_test_h100_iter1.json` (seq 64), `iter2.json` (MAX_ITERATIONS=2)

---

### Step 2 — Trim to ≤3 pages

```bash
wc -w REPORT.md   # target ~1200–1800
```

**Cut candidates** (in priority order):

1. **Appendix** — shrink local stand-in table to 3–4 rows or remove entirely for submission
2. **Path A practice subsection** — delete from `REPORT.md` (lives in `_notes/` if needed)
3. **H100 startup notes** — one sentence (KV headroom, probe OK) instead of full paragraph
4. **Duplicate screenshot callouts** — one reference per section is enough
5. **Iteration log** — keep 4 one-liners; do not expand into paragraphs
6. **Deliverables audit table** at bottom of appendix — remove (grader has README table)

**Do not cut:**

- Serving flag table with justifications
- `pass_rate_by_iteration` table and commentary
- SLO baseline vs final tables
- Agent value paragraph with explicit iter 0 / iter 2 citation
- Next steps (5 specific bullets)
- SLO MISS verdict with gap quantified (78.4 s above target)

---

### Step 3 — Update status header

Replace the top-of-file status block:

```markdown
**Status:** Submission-ready — H100 30B numbers, all deliverables present (2026-06-19).
```

Remove references to "screenshots missing" or `CAPTURE.md` as a blocker.

---

### Step 4 — Proofread for practice leakage

Search submission sections (§1–§5) for:

```bash
grep -n -E 'Path A|Nebius API|0\.6B|practice|placeholder|T500|WSL' REPORT.md
```

Allowed in **appendix only** (or remove appendix). Main body must read as a single H100 story.

---

### Step 5 — Screenshot visual review

Open each PNG and confirm it matches `REPORT.md` narrative:

| File | Must show |
|------|-----------|
| `vllm_manual_query.png` | 30B model returning SQL (probe or curl) |
| `grafana_serving.png` | Full `serving.json` dashboard, panels moving under 10 RPS load |
| `grafana_eval_run.png` | Dashboard during 30-question eval burst |
| `grafana_before.png` | Waiting queue + `num_requests_running` at cap (baseline) |
| `grafana_after.png` | Waiting queue cleared after `max-num-seqs` 32→64 |
| `langfuse_trace.png` | `generate_sql` → `verify` → optional `revise` waterfall |
| `langfuse_tags.png` | `run_type`, `batch_id`, `config_label` columns visible |

If a capture is wrong panel or flat Grafana: re-run shortest repro (60 s load or trace-sample) and re-capture only that file.

---

### Step 6 — Final `REPORT.md` section pass

Quick grader checklist per section:

| Section | Grader looks for |
|---------|------------------|
| §1 Serving | Every flag in `start_vllm.sh` has one-line MoE/workload rationale; final values reflect Phase 6 tuning |
| §2 Baseline eval | Execution-accuracy method stated; overall + per-iteration rates; honest loop commentary |
| §3 SLO | Baseline vs SLO table; 3–4 iteration lines in *saw → hypothesized → changed → result* form; before/after screenshot refs; quality table; HIT/MISS |
| §4 Agent value | **One paragraph**; cites `pass_rate_by_iteration`; ties to latency cost under load |
| §5 Next steps | Specific — no "add Kubernetes"; each bullet references a metric, panel, or eval failure |

---

### Step 7 — Submission gate

```bash
bash scripts/run_phase7_h100.sh summary
wc -w REPORT.md
test "$(wc -w < REPORT.md)" -le 1900 && echo "length OK" || echo "trim more"
```

Commit when satisfied (user request only).

---

## Re-capture playbook

Only if `summary` reports missing or bad screenshots:

| File | Shortest repro |
|------|----------------|
| `vllm_manual_query.png` | `bash scripts/run_phase7_h100.sh probe` (vLLM must be up) |
| `grafana_eval_run.png` | `bash scripts/run_phase7_h100.sh eval-baseline` (~45 s) |
| `grafana_serving.png` | `bash scripts/run_phase7_h100.sh load-baseline --duration=60` |
| `grafana_before.png` / `after.png` | Re-run 60 s load with baseline vs tuned config; capture mid-run |
| `langfuse_*.png` | `bash scripts/run_phase7_h100.sh trace-sample h100-trace manual` |

Stack (if VM cold):

```bash
docker compose up -d
bash scripts/start_vllm.sh
set -a && source .env && set +a
export VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507
export MAX_ITERATIONS=2
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

---

## Phase 7 completion checklist

### Local test phase (done)

- [x] Artifact audit — gaps documented in `_local_dev/phase_7_plan.md`
- [x] `REPORT.md` restructured into five submission sections
- [x] §1–§5 drafted; agent value cites `pass_rate_by_iteration`
- [x] `screenshots/CAPTURE.md` + `run_phase7_h100.sh`
- [x] Revise examples: `formula_1` (success), `financial` (failure)

### H100 measurement (done — 2026-06-19)

- [x] All eight `screenshots/*.png` captured from H100 / 30B runs
- [x] `results/eval_baseline.json` and `results/eval_after_tuning.json` — H100 data
- [x] `results/load_test_h100_*.json` — baseline + iterations + push-past
- [x] `REPORT.md` uses H100 numbers in eval and SLO sections
- [x] H100 serving flag table complete with justifications
- [x] SLO iteration log (4 lines) with before/after screenshot references
- [x] Honest SLO MISS verdict and quality tradeoff documented
- [x] Agent value paragraph updated with H100 eval percentages

### H100 polish (done — 2026-06-19)

- [x] `wc -w REPORT.md` ≤ ~1,800
- [x] Status header updated — submission-ready
- [x] Appendix removed for submission
- [x] Proofread: no Path A / 0.6B leakage in §1–§5
- [x] Visual review of all eight screenshots
- [x] `bash scripts/run_phase7_h100.sh summary` — all OK
- [x] Final read-through: report tells one coherent story (miss SLO, small loop lift, concurrency not KV-bound)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Report exceeds 3 pages | Appendix + startup notes + audit table | Trim appendix first; see Step 2 cut list |
| Eval section contradicts JSON | Manual typo during paste | Re-`jq` and fix tables |
| Agent value vague | Missing iteration citation | Quote iter 0: 40% → iter 2: 43.3% explicitly |
| "Next steps" generic | Not tied to evidence | Each bullet must name a metric or panel |
| Path A numbers in §3 | Draft not cleaned | `grep Path A REPORT.md`; move to `_notes/` only |
| Screenshot flat | No load during capture | Re-run 60 s load while capturing |
| `summary` shows missing PNG | Not committed or wrong path | `ls screenshots/`; re-capture if absent |
| Loop looks valuable in traces but flat in eval | Only 1/30 flipped | Cite both aggregate rates and `formula_1` example — already in draft |

---

## File touch map

| File | Action |
|------|--------|
| `REPORT.md` | **Primary** — trim, proofread, update status; no new numbers unless JSON re-run |
| `results/eval_*.json` | Read-only verify |
| `results/load_test_h100_*.json` | Read-only verify |
| `screenshots/*.png` | Visual review; re-capture only if bad |
| `scripts/run_phase7_h100.sh` | `summary` for audit |
| `scripts/start_vllm.sh` | Source for §1 — already matches report |
| `infra/grafana/.../serving.json` | Deliverable — no edits |
| `agent/graph.py`, `agent/prompts.py` | Deliverables — no edits |
| `_local_dev/phase_7_plan.md` | Reference — local skeleton plan |
| `_notes/final_phase_*.md` | Reference — not deliverables |

---

## Relationship to other phases

| Phase | What Phase 7 pulls from it |
|-------|---------------------------|
| **1 (vLLM)** | §1 flag table; `vllm_manual_query.png` |
| **2 (Grafana)** | `grafana_serving.png`; panel names in SLO diagnosis |
| **3 (Agent)** | Loop design for §4 agent value |
| **4 (Langfuse)** | `langfuse_trace.png`, `langfuse_tags.png` |
| **5 (Evals)** | §2 baseline; `grafana_eval_run.png` |
| **6 (SLOs)** | §3 iteration log, before/after, `eval_after_tuning.json`, MISS verdict |

Phase 7 does not unblock new engineering — it exposes gaps. If a number in the report cannot be explained, the fix is revisiting the phase that produced it, not adding prose.

---

## Time budget (polish-only session)

| Block | Duration | Notes |
|-------|----------|-------|
| `summary` + `jq` spot-check | 5 min | Confirm artifacts + number consistency |
| Screenshot visual review | 10 min | All eight PNGs |
| Trim `REPORT.md` | 15–25 min | Appendix + startup notes |
| Proofread + leakage grep | 10 min | §1–§5 only |
| Final read-through | 10 min | Coherent narrative |
| **Total** | **~45–60 min** | No VM required if files already on disk |

If re-capture needed: add 15–30 min per screenshot type (stack startup + short run).

---

## Grading alignment (what "strong" looks like)

Submission should demonstrate:

- **Serving (15%):** flags chosen for MoE 30B workload; `max-num-seqs=64` justified by waiting queue at 32, KV ~10%
- **Dashboard (15%):** screenshots show queue, latency, KV — answers "slow, and where?"
- **Agent (10%):** verify→revise with `MAX_ITERATIONS=2` cap; eval impact measured
- **Tracing (5%):** tags visible in `langfuse_tags.png`
- **Eval (15%):** execution-accuracy method; 43.3% overall; iter 0 vs iter 2 honest assessment
- **SLO (25%):** metric-grounded iteration log; waiting queue cleared; P95 still 83 s — architecture limit stated
- **Report (15%):** ≤3 pages, MISS quantified, specific next steps (cheaper verify, not Kubernetes)

---

## Submission narrative (one paragraph — for final read-through)

The report should read as: **30B self-hosted serving was tuned for concurrency (`max-num-seqs` 32→64) because Grafana showed a waiting queue while KV stayed ~10%; agent iteration cap (`MAX_ITERATIONS` 3→2) cut timeouts without hurting 43.3% eval accuracy; the verify→revise loop added only +3.3 pp on 30 questions (one DISTINCT fix); the 5 s P95 SLO at 10 RPS was missed by ~78 s because each agent request still runs two serial 30B calls — a serving knob cannot fix that architecture.**

---

## Next step after Phase 7

**Submit the repo** — complete `REPORT.md` + all deliverables. No Phase 8 in the README. Optional: user-requested git commit with final polish only.
