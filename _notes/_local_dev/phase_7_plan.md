# Phase 7 Plan — Local Test Environment

This plan adapts [README.md Phase 7 (Docs)](../README.md#phase-7-docs) for **local development on your machine** (WSL2 / laptop), not the cloud H100 VM. Per [assignment_remarks.md](assignment_remarks.md): draft and structure `REPORT.md` locally first; **submission-quality numbers, screenshots, and the final ≤3-page writeup** must come from the H100 + 30B run later.

---

## Goal

By the end of Phase 7 **locally** you should have:

- A **complete `REPORT.md` skeleton** with all five required sections stubbed or drafted
- An **artifact audit** — every row in the Final deliverables table accounted for (present, placeholder, or deferred to H100)
- Local/practice content clearly labeled (e.g. Path A Nebius, 0.6B stand-in) separate from H100 submission slots
- A draft **agent value** paragraph citing `pass_rate_by_iteration` from `results/eval_baseline.json`
- A draft **"what I'd do with more time"** section that is specific and tied to your Phase 6 diagnosis
- Confidence that the report fits **≤3 pages** once H100 numbers replace placeholders

**Final submission quality** (H100 only):

- `REPORT.md` complete with 30B H100 numbers only (no stand-in or Path A latency in SLO/eval sections)
- All 11 artifacts from the deliverables table present in the repo
- Honest verdict on SLO hit/miss and loop value — grading rewards diagnosis over green checkmarks (15%: report & communication)

---

## What Phase 7 is (and is not)

Phase 7 is **documentation and consolidation**, not new implementation. You are not building features — you are turning work from Phases 1–6 into a coherent, honest writeup.

```
Phases 1–6 (built + measured)
        │
        ├── results/eval_baseline.json
        ├── results/eval_after_tuning.json
        ├── results/load_test_*.json
        ├── screenshots/*.png
        ├── scripts/start_vllm.sh  (H100 config)
        └── infra/grafana/.../serving.json
        │
        ▼
  REPORT.md  (≤3 pages)
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
| (Feeds into) SLO diagnosis | 25% | Iteration log quality — finalize in Phase 6 section |
| (Feeds into) Eval rigor | 15% | Execution-accuracy methodology + loop analysis |

A missed SLO with metric-grounded diagnosis beats a hit you cannot explain. Say where you got stuck.

---

## `REPORT.md` required sections

README lists five sections. Map them to report headings and primary sources:

| # | README requirement | Suggested `REPORT.md` heading | Primary sources |
|---|-------------------|------------------------------|-----------------|
| 1 | Serving configuration (Phase 1), flags + one-line justification each | `## Serving configuration` | `scripts/start_vllm.sh`, Phase 1 probe notes, Phase 6 tuning log |
| 2 | Baseline eval (Phase 5), overall + per-iteration pass rate, commentary | `## Baseline evaluation` | `results/eval_baseline.json` → `summary.final_pass_rate`, `summary.pass_rate_by_iteration` |
| 3 | SLO (Phase 6), baseline vs SLO, iteration log, final numbers | `## SLO tuning` | `results/load_test_*.json`, `screenshots/grafana_before.png` / `after.png` |
| 4 | Agent value — one paragraph, cite per-iteration pass rate | `## Agent value` | Same eval JSON; Langfuse traces for revise examples |
| 5 | What you'd do with more time — specific | `## Next steps` | Phase 6 bottlenecks you did not fix (not "add Kubernetes") |

**Length:** aim at 2–3 pages (~1,200–1,800 words). Tables and iteration one-liners count toward the limit — prefer tight tables over prose.

---

## Final deliverables inventory

Use this table to audit the repo before and after the H100 session.

| File | What it is | Local status (now) | H100 required? |
|------|------------|-------------------|----------------|
| `REPORT.md` | Writeup ≤3 pages | **Partial** — Phase 1 + Phase 6 draft only | Finalize on H100 |
| `infra/grafana/provisioning/dashboards/serving.json` | Grafana dashboard | Present | Re-verify panels react under H100 load |
| `agent/graph.py`, `agent/prompts.py` | Agent implementation | Present | Same code; traces from 30B |
| `evals/run_eval.py` | Eval runner | Present | Re-run on H100 |
| `results/eval_baseline.json` | Baseline eval | Present (Path A / practice numbers) | **Replace** with H100 30B run |
| `results/eval_after_tuning.json` | Post-tuning eval | Present (Path A / MAX_ITERATIONS=2) | **Replace** with H100 final config |
| `screenshots/vllm_manual_query.png` | vLLM + manual SQL query | **Missing** | Capture on H100 |
| `screenshots/grafana_serving.png` | Full dashboard under load | **Missing** | Capture on H100 |
| `screenshots/langfuse_trace.png` | verify→revise waterfall | **Missing** | Capture on H100 (or Path A if revise visible) |
| `screenshots/langfuse_tags.png` | Trace list with metadata tags | **Missing** | Capture on H100 |
| `screenshots/grafana_eval_run.png` | Dashboard during baseline eval | **Missing** | Capture on H100 |
| `screenshots/grafana_before.png` | Before key tuning change | **Missing** | Capture on H100 |
| `screenshots/grafana_after.png` | After key tuning change | **Missing** | Capture on H100 |

**Local rule:** practice captures are fine for learning framing; **commit only H100 screenshots** for submission (per assignment_remarks).

---

## Current repo snapshot

As of Phase 7 local implementation:

| Area | State |
|------|-------|
| `REPORT.md` | **Complete skeleton** — five submission sections + appendix; H100 placeholders marked |
| `scripts/run_phase7_h100.sh` | H100 finalization helper (eval, load, trace-sample, artifact audit) |
| `screenshots/CAPTURE.md` | Checklist for eight submission PNGs |
| `results/eval_baseline.json` | Practice: `final_pass_rate: 0.40`, flat per-iteration |
| `results/eval_after_tuning.json` | Practice: `final_pass_rate: 0.37`, `formula_1` revise win |
| `results/load_test_*.json` | Path A baseline + MAX_ITERATIONS iteration |
| `screenshots/*.png` | Still missing — capture on H100 |
| Path A note | Nebius runs in appendix only; do not submit Path A SLO or eval numbers as final |

---

## Local vs H100 (what changes)

| README (VM / H100) | Local test phase |
|---|---|
| Complete `REPORT.md` with submission numbers | **Skeleton + drafts**; mark `<!-- H100: ... -->` or `*(fill on H100)*` placeholders |
| All screenshots from H100 runs | Inventory + optional practice captures; **defer submission PNGs** |
| `eval_baseline.json` / `eval_after_tuning.json` from 30B self-hosted vLLM | Keep practice JSONs; **overwrite on H100** |
| SLO numbers in report | Path A / local numbers in draft only; H100 section is authoritative |
| 2–3 pages final | Draft locally to check structure/length; trim after H100 paste-in |

**Local success looks like:** every report section exists, artifact gaps are listed, agent-value and next-steps paragraphs are drafted from real (practice) data, and you have a **H100 session checklist** — not a submission-ready PDF.

---

## Step-by-step (local)

### Step 0 — Artifact audit

Run a quick inventory:

```bash
# Required code + config
test -f infra/grafana/provisioning/dashboards/serving.json && echo OK serving.json
test -f agent/graph.py && test -f agent/prompts.py && echo OK agent
test -f evals/run_eval.py && echo OK eval runner

# Results
ls -la results/eval_baseline.json results/eval_after_tuning.json results/load_test*.json 2>/dev/null

# Screenshots (expect gaps locally)
ls -la screenshots/*.png 2>/dev/null || echo "screenshots/: none yet"

# Report length (rough page estimate: ~500 words per page)
wc -w REPORT.md
```

Record gaps in a scratch list at the top of `REPORT.md` or in this plan's checklist.

---

### Step 1 — Restructure `REPORT.md`

Replace phase-numbered drafts with the **five submission sections** README expects. Suggested outline:

```markdown
# Assignment Report

## Serving configuration
### Production (H100, Qwen3-30B-A3B)
| Flag | Value | Justification |
...

### Local development (reference only — not submitted)
Brief note on stand-in model / Path A; pointer to `start_vllm_local.sh`.

## Baseline evaluation
### Method
Execution-accuracy: canonicalized row sets, not string match on SQL.

### Results (H100)
| Metric | Value |
| final_pass_rate | ... |
| pass_rate_by_iteration | iter 0 / 1 / 2 |
| avg_agent_iterations | ... |

### Commentary
Flat per-iteration curve → loop did / did not lift aggregate pass rate.
Cite 1–2 concrete question IDs where revise helped or failed.

## SLO tuning
### Platform SLO
P95 agent latency < 5s, 10+ RPS, 300s window.

### Baseline vs SLO (H100)
| Metric | Baseline | SLO target | Pass? |

### Iteration log
1. saw X → hypothesized Y → changed Z → result W
2. ...

### Final numbers
Best p95, achieved RPS, error rate.

### Quality after tuning
Table: eval_baseline vs eval_after_tuning (pass rates, agent_ok_rate).

### Verdict
SLO HIT / MISS — gap quantified.

![Before](../screenshots/grafana_before.png)
![After](../screenshots/grafana_after.png)

## Agent value
One paragraph: did verify→revise earn its latency cost?
Cite pass_rate_by_iteration and avg_agent_iterations.
Honest if loop is flat — say what would need to change (prompts, verifier strictness).

## Next steps
3–5 specific bullets tied to your metrics, e.g.:
- Enable prefix caching because schema tokens repeat across generate/verify/revise
- Tune --max-num-seqs because waiting queue rose before KV saturated
- Tighten verify prompt on JOIN/DISTINCT failures seen in eval item formula_1
Avoid vague infra wishes ("add Kubernetes", "scale horizontally").

## Appendix (optional, does not count toward page limit if grader reads main sections only)
Local smoke-test notes, Path A practice runs — keep short or omit from submission.
```

**Migrate existing content:** move Phase 1 H100 table and local smoke notes into `## Serving configuration`; move Phase 6 Path A draft into an appendix or a clearly labeled `### Practice (Path A — not submitted)` subsection until H100 replaces it.

---

### Step 2 — Draft §1 Serving configuration

**Locally:**

- Keep the filled **local stand-in** flag table (already in `REPORT.md`) under a "local only" subheading.
- Leave the **H100 production table** as placeholders with the knobs you plan to tune (`--max-num-seqs`, `--gpu-memory-utilization`, `--max-model-len`, prefix caching, etc.) — copy candidates from [phase_6_plan.md suggested H100 tuning order](phase_6_plan.md#suggested-h100-tuning-order-for-vm-session).

**On H100:** fill every flag in `scripts/start_vllm.sh` with a one-line justification tied to this workload (MoE 30B, ~2K prompt, 2–3 short LLM calls per agent request).

---

### Step 3 — Draft §2 Baseline evaluation

Pull numbers from JSON (practice now, H100 later):

```bash
jq '.summary | {final_pass_rate, pass_rate_by_iteration, avg_agent_iterations, agent_ok_rate, iteration_histogram}' \
  results/eval_baseline.json
```

**Commentary prompts** (answer in 3–5 sentences):

- Is `pass_rate_by_iteration` flat or rising through iter 0 → 1 → 2?
- What does `iteration_histogram` say about how often revise runs?
- Is `agent_ok_rate` much higher than `final_pass_rate`? (verifier accepting wrong SQL)
- Name one eval item where revise fixed execution accuracy and one where it did not.

**Current practice data** (Path A / Nebius): final 40%, flat across iterations — draft the honest "loop did not lift aggregate pass rate" paragraph now; update numbers on H100.

**Screenshot:** `screenshots/grafana_eval_run.png` — capture during `run_eval.py` on H100 with dashboard visible (all panel groups).

---

### Step 4 — Draft §3 SLO tuning

**Locally:** keep Path A iteration log as practice; add a prominent note that submission SLO numbers come from H100 self-hosted vLLM only.

**H100 content must include:**

1. Baseline table: `latency_p95`, `latency_p50`, `achieved_rps`, `ok/total`, `--rps 10 --duration 300`
2. Every iteration in *saw → hypothesized → changed → result* form (3–4 iterations normal)
3. Reference to before/after screenshots around the iteration that moved the targeted metric
4. `eval_baseline.json` vs `eval_after_tuning.json` after final config
5. Verdict: HIT or MISS with gap (e.g. "P95 6.2s at 10 RPS — miss by 1.2s")

**Screenshot pair:** frame the same Grafana time range and panels for `grafana_before.png` and `grafana_after.png` — the change that moved queue depth, TTFT, or KV cache, not just any two runs.

---

### Step 5 — Draft §4 Agent value (one paragraph)

Template — fill with your numbers:

> The verify→revise loop {did / did not} improve execution accuracy on this eval set. Overall pass rate was {X%} with per-iteration rates {iter0: A%, iter1: B%, iter2: C%} — {flat / rising}, so {stopping after iter 0 would have been equivalent / iter 1 recovered N additional questions}. Average agent iterations was {M} (histogram: …). The loop's value is {justified / not justified} given {latency cost of revise seen in Phase 6 / specific traces in Langfuse}. {If flat: failures are predominantly first-attempt SQL shape errors (JOINs, DISTINCT, filters), so gains require prompt or verifier changes, not more revise rounds.}

Cite `pass_rate_by_iteration` explicitly — graders look for this (README §4, 15% eval + 15% report).

---

### Step 6 — Draft §5 Next steps (specific)

Weak (do not submit):

- "Deploy to Kubernetes"
- "Add more GPUs"
- "Use a bigger model"

Strong (tie to your dashboard / eval evidence):

- "Enable `--enable-prefix-caching` because generate and verify share the same schema block — Langfuse shows ~1.5K repeated prefix tokens per request."
- "Raise `--max-num-seqs` from 8 to 16 because baseline load test showed `vllm_num_requests_waiting` pegged while KV was at 62%."
- "Add eval cases for DISTINCT/JOIN failures; formula_1 iter-1 fix shows revise can work when verify rejects."
- "Decouple verify from a full second LLM call — structured JSON check against `EXPLAIN` or row-count bounds for latency."

Draft 3–5 bullets locally from Phase 6 hypotheses; refine after H100.

---

### Step 7 — Length and honesty pass

```bash
wc -w REPORT.md   # target ~1200–1800 for 2–3 pages
```

- Remove duplicate tables (local + H100 same metric).
- Mark all non-H100 numbers as practice or omit from submission sections.
- Ensure iteration log lines are one sentence each, not paragraphs.
- State misses clearly (SLO, loop value, quality regression after tuning).

---

### Step 8 — Screenshot capture playbook

Create `screenshots/` if missing:

```bash
mkdir -p screenshots
```

| File | When to capture | What to show |
|------|-----------------|--------------|
| `vllm_manual_query.png` | Phase 1 on H100 | Terminal or UI with chat completion returning SQL against 30B vLLM |
| `grafana_serving.png` | Phase 2 or 6 load test | Full `serving.json` dashboard, panels reacting (latency, throughput, KV) |
| `langfuse_trace.png` | Phase 4 or 6 trace sample | Single trace: `generate_sql` → `verify` → `revise` → … waterfall |
| `langfuse_tags.png` | Same session | Trace list with `run_type`, `batch_id`, `config_label` columns visible |
| `grafana_eval_run.png` | Phase 5 H100 eval | Dashboard during `run_eval.py` (30 questions) |
| `grafana_before.png` | Phase 6 pre-change | Panel that motivated the hypothesis (e.g. waiting queue) |
| `grafana_after.png` | Phase 6 post-change | Same panel layout after one-knob change |

**Path A locally:** Langfuse screenshots may be capturable; Grafana vLLM panels stay flat — defer `grafana_*.png` to H100.

---

## H100 finalization session (submission)

Run in order — single VM session if possible:

1. **Stack:** `docker compose up -d`, `bash scripts/start_vllm.sh`, agent with final `MAX_ITERATIONS`, `.env` → `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`
2. **Phase 1 screenshot:** manual SQL probe → `screenshots/vllm_manual_query.png`
3. **Phase 5:** `uv run python evals/run_eval.py --out results/eval_baseline.json` — capture `screenshots/grafana_eval_run.png`
4. **Phase 6 baseline:** `uv run python load_test/driver.py --rps 10 --duration 300 --config-label h100-30b-baseline --out results/load_test_h100_baseline.json` — capture `screenshots/grafana_serving.png`
5. **Phase 6 iterations:** one knob per run; save JSON per iteration; before/after screenshots on the meaningful change
6. **Phase 6 final eval:** `uv run python evals/run_eval.py --out results/eval_after_tuning.json`
7. **Phase 4 screenshots:** Langfuse trace + tags from eval or `trace-sample` load run
8. **REPORT.md:** paste H100 numbers, remove practice-only sections, `wc -w` trim to ≤3 pages
9. **Final audit:** every row in deliverables table present

---

## Phase 7 completion checklist

### Local test phase (now)

- [x] Artifact audit done — gaps documented (screenshots, H100 JSONs, report sections)
- [x] `REPORT.md` restructured into five submission sections (skeleton)
- [x] §1 Serving: local table in appendix; H100 table templated
- [x] §2 Baseline eval: drafted from `eval_baseline.json` (practice numbers labeled)
- [x] §3 SLO: Path A migrated to appendix; H100 placeholders for verdict + iterations
- [x] §4 Agent value: one paragraph with `pass_rate_by_iteration` cited
- [x] §5 Next steps: 5 specific bullets tied to metrics
- [x] `wc -w REPORT.md` — ~1500 words (trim appendix before submit if needed)
- [x] `screenshots/` directory + `CAPTURE.md` checklist; `run_phase7_h100.sh` ready
- [x] Revise examples cited: `formula_1` (success), `financial` (failure)

### H100 / submission (later)

- [ ] All eight `screenshots/*.png` captured from H100 / 30B runs
- [ ] `results/eval_baseline.json` and `results/eval_after_tuning.json` overwritten with H100 data
- [ ] `REPORT.md` uses **only** H100 numbers in eval and SLO sections
- [ ] H100 serving flag table complete — one justification per flag
- [ ] SLO iteration log (3–4 lines) with before/after screenshot references
- [ ] Honest SLO verdict and quality tradeoff after tuning documented
- [ ] Final deliverables table — all 11 paths present
- [ ] Report ≤3 pages; proofread for "practice" / "Path A" leakage into submission sections

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Report exceeds 3 pages | Duplicate local+H100 tables, long appendix | One table per metric; move local notes to appendix or delete |
| Eval section contradicts JSON | Manual typo | Always `jq` copy from `results/*.json` |
| Agent value paragraph vague | No iteration citation | Quote `pass_rate_by_iteration` numbers explicitly |
| "Next steps" generic | Not tied to Phase 6 | Each bullet must reference a metric, panel, or eval failure mode |
| Missing screenshot | Skipped during H100 session | Re-run shortest repro (eval batch, 60s load) to capture |
| Grafana flat in screenshot | No load during capture | Run `load_test/driver.py` or `run_eval.py` while capturing |
| Path A numbers in final report | Draft not cleaned | Search report for "Nebius", "Path A", "0.6B" before submit |
| Loop looks valuable in traces but flat in eval | Few revise successes | Cite both aggregate rates and single-question example (e.g. formula_1) |

---

## File touch map

| File | Action |
|------|--------|
| `REPORT.md` | **Primary output** — structure, draft locally, finalize on H100 |
| `results/eval_baseline.json` | Read for §2 and §4; replace on H100 |
| `results/eval_after_tuning.json` | Read for §3 quality table; replace on H100 |
| `results/load_test_*.json` | Read for §3 SLO tables |
| `scripts/start_vllm.sh` | Source for §1 H100 flag table |
| `screenshots/*.png` | Capture on H100; eight files required |
| `infra/grafana/.../serving.json` | Deliverable — no report prose unless citing panels |
| `agent/graph.py`, `agent/prompts.py` | Deliverables — mention in agent value if prompts changed during tuning |
| `phase_*_plan.md` | Reference only — not a deliverable |

---

## Relationship to other phases

| Phase | What Phase 7 pulls from it |
|-------|---------------------------|
| **1 (vLLM)** | Flag table + justifications; `vllm_manual_query.png` |
| **2 (Grafana)** | `grafana_serving.png`; panel names in SLO diagnosis |
| **3 (Agent)** | Loop design context for agent value paragraph |
| **4 (Langfuse)** | `langfuse_trace.png`, `langfuse_tags.png`; trace examples in writeup |
| **5 (Evals)** | `eval_baseline.json`, `grafana_eval_run.png`, per-iteration analysis |
| **6 (SLOs)** | Iteration log, before/after Grafana, `eval_after_tuning.json`, verdict |

Phase 7 does not unblock new engineering — it exposes gaps. If the report cannot explain a number, revisit the phase that produced it.

---

## Grading alignment (what "strong" looks like)

From README grading table — Phase 7 submission should demonstrate:

- **Serving (15%):** flags chosen for this workload, not defaults; one-line MoE / prompt-shape / latency rationale each
- **Dashboard (15%):** screenshots show panels that answer "slow, and where in the lifecycle?"
- **Agent (10%):** verify→revise with iteration cap referenced in agent value
- **Tracing (5%):** tags visible in `langfuse_tags.png`, used in SLO narrative
- **Eval (15%):** execution-accuracy methodology stated; overall + per-iteration rates; honest loop assessment
- **SLO (25%):** metric-grounded iteration log with evidence the targeted metric moved
- **Report (15%):** ≤3 pages, honest misses, specific next steps

---

## Next step after Phase 7

**H100 VM session** — execute the [H100 finalization session](#h100-finalization-session-submission) above, then treat Phase 7 local checklist H100 items as the submission gate. No Phase 8 in the README; submission is the complete repo + `REPORT.md`.
