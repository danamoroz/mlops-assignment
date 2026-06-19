# Phase 6 Plan — Nebius H100 VM (Final / Submission Environment)

This plan adapts [README.md Phase 6 (SLOs)](../README.md#phase-6-slos) for the **Nebius H100 slot**. It builds on what we already validated locally in [`_local_dev/phase_6_plan.md`](_local_dev/phase_6_plan.md). Local Phase 6 taught the load-test + diagnosis workflow (Path A and/or 0.6B stand-in); this session runs the **real SLO attempt** on self-hosted 30B, produces submission numbers, Grafana before/after screenshots, and `results/eval_after_tuning.json`.

Per [assignment_remarks.md](_local_dev/assignment_remarks.md): practice the workflow locally first; **submission artifacts** (SLO numbers in `REPORT.md`, `screenshots/grafana_before.png` / `grafana_after.png`, `results/eval_after_tuning.json`) must come from **H100 + Qwen3-30B** only.

---

## Goal

By the end of Phase 6 on Nebius you should have:

- Baseline load test at **10 RPS × 300 s** against the agent on 30B, with Grafana serving dashboard watched live
- **3–4 metric-grounded tuning iterations**, each one knob, each with a line in `REPORT.md`: *"saw X → hypothesized Y → changed Z → result was W"*
- A **push-past-SLO** run if baseline already passes (raise `--rps` until something breaks; document what fails first)
- **`screenshots/grafana_before.png`** and **`screenshots/grafana_after.png`** — same panel layout around the iteration that moved the targeted metric
- **`results/eval_after_tuning.json`** on the **final tuned config** — compare to H100 `results/eval_baseline.json` (43.3% pass rate, 2026-06-19)
- An **honest verdict** in `REPORT.md`: SLO hit, or missed with gap quantified (25% of grade is diagnosis quality, not just a green check)

**Out of scope for Phase 6** (Phase 7): final `REPORT.md` polish (≤3 pages), word-count trim, consolidating appendix. Phase 6 only needs SLO numbers, iteration log, quality comparison, and screenshots.

---

## The SLO (what you are measuring)

From Phase 1 / README — **end-to-end agent latency**, not raw vLLM latency alone:

> **P95 end-to-end agent latency under 5 seconds, 10+ RPS (1 RPS = 1 full agent run per second) over a 5-minute window.**

| Dimension | Meaning |
|-----------|---------|
| **End-to-end** | Wall clock from `POST /answer` to full response — 2–3 LLM calls (generate → verify → optional revise), SQLite execution, Python overhead |
| **P95** | 95th percentile of **successful** request latencies during the window |
| **10+ RPS** | Sustained offered load: driver fires ≥10 new agent requests per second for 300 seconds (~3000 total) |
| **5-minute window** | `--duration 300` on the load driver |

**Pass criteria:** `latency_p95 < 5.0` **and** `requested_rps >= 10` **and** low timeout/error rate (`ok / total_requests` near 1.0).

**Workload context** (from Phase 1 / 5 on H100):

| Dimension | Profile |
|-----------|---------|
| Model | `Qwen/Qwen3-30B-A3B-Instruct-2507` — MoE, ~3B active params/token |
| Hardware | 1× H100 80GB |
| Prompt size | ~1.5–3K tokens (question + DB schema) |
| Output | Short SQL / JSON verify verdict |
| Calls per user request | ~2–3 dependent LLM calls (`avg_agent_iterations` ≈ 1.67 at eval) |
| Idle KV headroom | ~15 GiB KV cache after 57 GiB weights (`gpu-memory-utilization 0.92`) |

At 10 RPS with 2–3 LLM calls each, vLLM sees **20–30+ concurrent sequences** under steady state — the starting `--max-num-seqs 32` from Phase 1 is a reasonable seed but may need tuning.

---

## What you are building (context)

Phase 6 closes the loop between Phase 1 serving config and real concurrent traffic. The load driver hits the **agent**, not vLLM directly — Grafana vLLM panels explain *why* agent latency moved.

```
load_test/perf_pool.jsonl  (1500 questions)
        │
        ▼
  load_test/driver.py  ──► POST /answer  (async, at --rps for --duration)
        │                      │
        │                      ├── agent/graph.py  (2–3 LLM calls per request)
        │                      └── vLLM :8000
        │
        ├── records per-request latency_seconds, status
        │
        ▼
  results/load_test_*.json  (summary: p50/p95/p99, achieved_rps, errors)
        │
        ├── Grafana serving.json  ──► vLLM latency, throughput, KV cache, queue
        └── Langfuse  ──► filter run_type=load_test, batch_id=... (trace-sample after load)
```

### Load driver (already implemented)

| Flag | Default | H100 SLO run |
|------|---------|--------------|
| `--rps` | `8.0` | **`10`** |
| `--duration` | `300` | **`300`** |
| `--timeout` | `120` | **`120`** (raise to `180` only if mass timeouts on slow traces) |
| `--drain-timeout` | `60` | **`600`** via `run_phase7_h100.sh` — let in-flight agent runs finish |
| `--config-label` | none | **`h100-30b-baseline`**, then `h100-30b-iter1`, … per iteration |
| `--batch-id` | auto | Distinct per run, e.g. `h100-baseline-300s` |
| `--out` | `results/load_test.json` | **`results/load_test_h100_baseline.json`**, etc. |

Each request sends Langfuse tags: `run_type=load_test`, `source=load_driver`, `db_id`, `batch_id`, `seq`, optional `config_label`.

Use **distinct `batch_id` and `config_label` per tuning iteration** so traces and JSON files do not mix.

### Grafana panels to watch (`serving.json`)

| Panel group | What it tells you | Moves first when… |
|-------------|-------------------|-------------------|
| **Time to first token (percentiles)** | Prefill / queue delay before generation starts | Prompt too long, batch queue full, GPU saturated on prefill |
| **End-to-end request latency (percentiles)** | Total vLLM request time per LLM call | Any bottleneck in the inference path |
| **Prefill vs decode (p95)** | Slowness is input processing vs token generation | Long schemas → prefill; short outputs → often prefill-bound |
| **Queue & inter-token latency (p95)** | Scheduler backlog, decode smoothness | `max-num-seqs` too low, KV cache full |
| **Request concurrency** (running / waiting) | How backed up vLLM is | Waiting ↑ → concurrency or KV limit before raw compute |
| **Token throughput** | Actual generation rate | Flat under rising load → saturated |
| **GPU KV cache usage** | Headroom for more concurrent requests | High usage + waiting queue → KV memory or seq limit |
| **Preemptions & queue depth** | Scheduler evicting/reordering | KV pressure; latency variance spikes |

**Agent-side signals** (driver JSON + Langfuse, not on vLLM dashboard):

- Agent P95 >> vLLM e2e P95 → multiple serial LLM calls or revise loops dominating
- Timeouts in driver summary → agent or vLLM cannot keep up with offered RPS
- Langfuse waterfall: 3 LLM spans vs 2 → revise fired; compare slow traces

---

## What we already have locally (don't re-invent)

Validated on WSL2 / laptop and Path A (2026-06), per [`phase_6_plan.md`](_local_dev/phase_6_plan.md):

| Item | Local status | On Nebius |
|------|--------------|-----------|
| Load driver | `load_test/driver.py` — async RPS, tags, summary JSON | **No code changes** — run at `--rps 10 --duration 300` |
| Tag schema | `run_type=load_test`, `batch_id`, `config_label` | Same keys; H100 labels only |
| Diagnosis workflow | One-knob iteration, Grafana panel targeting | **Primary surface is Grafana** (unlike Path A) |
| Path A practice | P95 167s → 115s with `MAX_ITERATIONS` 3→2 (−31%) | Informs agent knob; **not submission numbers** |
| Local vLLM practice | KV / waiting queue moves on 0.6B | Maps to H100 `max-num-seqs` / KV hypotheses |
| Helper script | `scripts/run_phase6_path_a.sh` (Path A only) | Use **`scripts/run_phase7_h100.sh`** on H100 |
| Trace sample | `scripts/phase6_trace_sample.py` | Re-run after load with `LANGFUSE_DISABLED=1` during load |

**Do not copy Path A or local stand-in p95/RPS into `REPORT.md` submission section.** Those live in `REPORT.md` appendix only.

**Do not stack random flags.** README: if you are on iteration 7 without a metric that moved, stop and re-read the dashboard.

---

## What we already have on H100 (Phases 1–5)

From [Phase 1](final_phase_1.md) / [Phase 5](final_phase_5.md) session (2026-06-19):

| Item | H100 status |
|------|-------------|
| vLLM config | `scripts/start_vllm.sh` — BF16 30B, `max-num-seqs 32`, `gpu-memory-utilization 0.92`, `max-model-len 8192`, prefix caching + chunked prefill on |
| Agent | `:8001`, Langfuse enabled, `MAX_ITERATIONS=3` (default env) |
| Baseline eval | `results/eval_baseline.json` — **43.3%** `final_pass_rate`, iter 0: 40% → iter 2: 43.3% |
| Grafana | `screenshots/grafana_eval_run.png` captured; serving dashboard verified under eval burst |
| Load test | **Not run yet** — no `results/load_test_h100_*.json` |
| Phase 6 screenshots | `grafana_serving.png`, `grafana_before.png`, `grafana_after.png` — **pending** |

Starting production config (Phase 1 — tune in Phase 6):

```bash
# scripts/start_vllm.sh (current)
--dtype bfloat16
--max-model-len 8192
--gpu-memory-utilization 0.92
--max-num-seqs 32
--enable-prefix-caching
--enable-chunked-prefill
```

Tuning order documented in `REPORT.md`: `max-num-seqs` → KV headroom → `max-model-len` → prefix caching → agent `MAX_ITERATIONS` (measure eval impact).

---

## Local vs Nebius (what changes)

| Local test (WSL / 0.6B or Path A) | Nebius H100 VM |
|-----------------------------------|----------------|
| Same commands, P95 in tens–hundreds of seconds | **Real SLO target: P95 < 5s at 10 RPS** |
| Tune `start_vllm_local.sh` for practice | Tune **`scripts/start_vllm.sh` only** |
| Path A: no Grafana vLLM panels | **Grafana is primary diagnosis surface** |
| Directional iteration lines in notes | **Final iteration log in `REPORT.md`** |
| Practice `eval_after_tuning.json` | **H100 `eval_after_tuning.json` overwrites practice file** |
| Optional Grafana screenshots | **Required** `grafana_before.png`, `grafana_after.png`, `grafana_serving.png` |
| Langfuse may drop spans under load | **`LANGFUSE_DISABLED=1` during load** + `trace-sample` after |

Local success was workflow muscle memory. H100 success is **submission-grade numbers + metric-grounded diagnosis**.

---

## Prerequisites (Nebius VM)

Confirm before starting Phase 6 (most from Phases 0–5):

- [ ] **Phase 0** — `docker compose up -d`, port forwards **3000** (Grafana), **3001** (Langfuse), **8001** (agent)
- [ ] **Phase 1** — 30B vLLM healthy on `:8000`, Prometheus target `vllm` UP
- [ ] **Phase 2** — `serving.json` dashboard panels react under load (verified at eval burst)
- [ ] **Phase 3** — agent on `:8001`, verify+revise loop wired
- [ ] **Phase 4** — Langfuse traces with `run_type`, `batch_id`, `config_label`
- [ ] **Phase 5** — `results/eval_baseline.json` on H100 (43.3% pass rate)
- [ ] **`.env`** — `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, no Path A `VLLM_BASE_URL` override
- [ ] **`load_test/perf_pool.jsonl`** — 1500 lines present

Quick preflight:

```bash
cd ~/mlops-assignment
bash scripts/run_phase7_h100.sh preflight
wc -l load_test/perf_pool.jsonl    # expect 1500
jq '.summary' results/eval_baseline.json
```

Stack in **three terminals** (or tmux):

```bash
# Terminal 1 — observability + vLLM
docker compose up -d
bash scripts/start_vllm.sh

# Terminal 2 — agent (restart after graph.py or MAX_ITERATIONS env change)
set -a && source .env && set +a
export VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507
# Optional during load to reduce Langfuse overhead:
# LANGFUSE_DISABLED=1 uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001

# Terminal 3 — load tests + jq analysis
```

---

## Execution steps

### Step 0 — Set up iteration tracking

`REPORT.md` already has a `## SLO tuning` stub with H100 placeholders. Before the first load run, open Grafana and confirm panel layout:

1. **Grafana** — http://localhost:3000 → **vLLM serving** dashboard
2. Time range: **Last 15 minutes**, refresh **5s**
3. Arrange visible at once: **e2e latency p95**, **TTFT p95**, **running/waiting**, **KV cache usage**
4. Create scratch log: `_notes/phase6_h100_scratch_log.md` (optional but recommended)

---

### Step 1 — Optional smoke load (short, low RPS)

Validate the pipeline before committing to a 5-minute × 10 RPS run (~5–8 min wall + drain):

```bash
uv run python load_test/driver.py \
  --rps 2 \
  --duration 60 \
  --batch-id h100-smoke-60s \
  --config-label h100-30b-baseline \
  --out results/load_test_h100_smoke.json
```

Confirm Grafana panels move. Inspect:

```bash
jq '.summary' results/load_test_h100_smoke.json
```

If connection errors or mass timeouts at 2 RPS, fix stack before baseline — do not proceed to 10 RPS blind.

---

### Step 2 — Baseline load test (SLO attempt)

**Capture `screenshots/grafana_serving.png`** during this run — full dashboard with panels reacting.

```bash
bash scripts/run_phase7_h100.sh load-baseline
# equivalent:
# uv run python load_test/driver.py \
#   --rps 10 --duration 300 --timeout 120 --drain-timeout 600 \
#   --batch-id h100-baseline-300s \
#   --config-label h100-30b-baseline \
#   --out results/load_test_h100_baseline.json
```

Record baseline vs SLO:

| Field | Your value | SLO target |
|-------|------------|------------|
| `latency_p95` | ? | < 5.0 s |
| `latency_p50` | ? | — |
| `requested_rps` | 10 | ≥ 10 |
| `achieved_rps` | ? | close to 10 |
| `ok / total_requests` | ? | ~100% |
| `timeouts` | ? | 0 |

**README step 2:** If baseline **passes**, still run a push-past run (Step 6). If it **misses**, you already have your first data point — proceed to diagnosis.

---

### Step 3 — Diagnose (do not guess fixes yet)

While baseline (or overload) run is visible on Grafana, answer:

1. **Which panel moved first** as load ramped?
2. **Where is time spent?** Compare TTFT vs e2e on vLLM panels.
3. **Agent vs vLLM gap?** If agent P95 >> vLLM e2e P95, serial LLM calls dominate — serving-only tuning may not fix SLO.
4. **Hypothesis in one sentence** tied to a metric, e.g.:
   - *"`num_requests_waiting` climbed to 12 while KV cache hit 88% → concurrency limited by KV headroom, not compute."*
   - *"TTFT p95 spiked to 2.1s, decode flat → prefill-bound on long schema prompts despite chunked prefill."*
   - *"Agent P95 8.2s but vLLM e2e p95 1.4s → ~2.5 serial LLM calls per request at 10 RPS; agent architecture is the bottleneck."*

**Langfuse drill-down** (after load, not during — see Step 3b):

```bash
bash scripts/run_phase7_h100.sh trace-sample h100-baseline-traces h100-30b-baseline
```

Filter http://localhost:3001 → `run_type=load_test`, `batch_id=h100-baseline-traces`. Sort slow traces; count LLM spans (`generate_sql`, `verify`, `revise`).

**Do not change config until you can point at a Grafana panel or trace.**

---

### Step 3b — Langfuse under load

During **10 RPS × 300 s**, Langfuse often drops spans (`Failed to export span batch` in agent logs). Recommended pattern:

| Step | Agent setting | Purpose |
|------|---------------|---------|
| Load test | `LANGFUSE_DISABLED=1` | Stable load numbers; no export backpressure |
| Trace sample | Langfuse **on** | 5 sequential requests via `trace-sample` with same tags |

Restart agent between modes if you toggled `LANGFUSE_DISABLED`.

---

### Step 4 — Change one thing, re-run, confirm metric moved

Pick **one** lever per iteration. Suggested H100 order (matches common bottlenecks for this workload):

| Priority | Knob | Target metric | Notes |
|----------|------|---------------|-------|
| 1 | `--max-num-seqs` (e.g. 32 → 48 or 32 → 24) | `waiting` queue, KV usage, agent P95 | Primary concurrency vs latency tradeoff |
| 2 | `--gpu-memory-utilization` (e.g. 0.92 → 0.95) | KV headroom ↑ | More concurrent seqs if VRAM allows |
| 3 | `--max-model-len` (8192 → 6144 or 4096) | KV usage ↓ | Only if prompts fit; frees KV blocks |
| 4 | `--max-num-batched-tokens` (add explicitly) | TTFT, throughput under mixed prefill/decode | If prefill queue bound |
| 5 | Prefix caching verification | Prefix cache hit rate (if panel added) | Already enabled — confirm hits on shared schema |
| 6 | Agent `MAX_ITERATIONS` (env `MAX_ITERATIONS=2`) | Agent P95 ↓ | Path A showed −31% P95; H100 eval was 43.3% → 40% locally on Path A — **re-measure on H100** |

After editing `scripts/start_vllm.sh` (or agent env):

1. **Restart vLLM** (and agent if `MAX_ITERATIONS` changed)
2. New `--config-label` (e.g. `h100-30b-maxseqs-48`)
3. New `--batch-id` (e.g. `h100-iter1-maxseqs48-300s`)
4. Re-run **same** load: `--rps 10 --duration 300`
5. Compare `jq '.summary'` before vs after
6. Confirm **targeted Grafana panel** moved in the expected direction
7. Ask: **did agent P95 move with it?**

**Screenshot the iteration that moved the needle:**

- **Before:** `screenshots/grafana_before.png` — capture **mid-run** on baseline (or pre-change config) showing the panel that motivated the hypothesis (e.g. waiting queue, KV cache)
- **After:** `screenshots/grafana_after.png` — same dashboard layout, same panels, post-change run

Write one line in `REPORT.md`:

> *"saw waiting queue at 14 and KV cache 91% at 10 RPS → hypothesized max-num-seqs too conservative for KV headroom → changed max-num-seqs 32→48 → waiting dropped to 4, agent P95 6.8s→5.1s, ok rate 99.2%"*

Negative results count — document when vLLM improved but agent P95 did not.

Example iteration run:

```bash
# after editing start_vllm.sh
bash scripts/run_phase7_h100.sh load \
  --batch-id=h100-iter1-maxseqs48 \
  --config-label=h100-30b-maxseqs-48 \
  --out=results/load_test_h100_iter1.json
```

---

### Step 5 — Iterate (3–4 rounds)

README expects **3–4 iterations** on the VM. Each produces:

- [ ] One line in `REPORT.md` (*saw → hypothesized → changed → result*)
- [ ] `results/load_test_h100_<label>.json` saved
- [ ] Grafana observation (before/after on the meaningful change)
- [ ] Optional: `trace-sample` with new `batch_id` for slow-request inspection

**Stop guessing at iteration 7.** Re-read dashboard and Langfuse if metrics are flat.

Keep a table in scratch log:

| Iter | config_label | change | p95 | ok rate | notes |
|------|--------------|--------|-----|---------|-------|
| baseline | h100-30b-baseline | — | | | |
| 1 | h100-30b-… | max-num-seqs … | | | |
| 2 | … | … | | | |

---

### Step 6 — Push past the SLO (if baseline passes)

If you hit P95 < 5s at 10 RPS on first try, README still wants you to **increase load until something breaks**:

```bash
bash scripts/run_phase7_h100.sh load \
  --rps=12 --duration=120 \
  --batch-id=h100-push-12rps \
  --config-label=h100-30b-final \
  --out=results/load_test_h100_push_12rps.json
```

Then try `--rps=15`. Document which metric fails first (timeouts, waiting queue, KV preemptions, TTFT cliff).

---

### Step 7 — Final config + eval quality check

Lock **`scripts/start_vllm.sh`** (and agent env if changed) to the best SLO config. Run post-tuning eval:

```bash
bash scripts/run_phase7_h100.sh eval-final
```

Compare to H100 baseline:

```bash
jq '.summary | {final_pass_rate, pass_rate_by_iteration, avg_agent_iterations, agent_ok_rate}' \
  results/eval_baseline.json
jq '.summary | {final_pass_rate, pass_rate_by_iteration, avg_agent_iterations, agent_ok_rate}' \
  results/eval_after_tuning.json
```

If tuning regressed quality (e.g. `MAX_ITERATIONS=2` drops pass rate below 43.3%), document the tradeoff in `REPORT.md` — latency wins that destroy accuracy are a valid finding.

**H100 baseline reference (2026-06-19):**

| Metric | Baseline |
|--------|----------|
| `final_pass_rate` | 43.3% |
| `pass_rate_by_iteration` | iter 0: 40% / iter 1: 43.3% / iter 2: 43.3% |
| `avg_agent_iterations` | 1.67 |
| `agent_ok_rate` | 76.7% |

---

### Step 8 — Fill `REPORT.md` SLO section

Update the existing stub (do not wait for Phase 7 to paste numbers):

1. **Baseline vs SLO** — table with p95, RPS, error rate, pass/fail
2. **Iteration log** — all *saw → hypothesized → changed → result* lines
3. **Final numbers** — best achieved p95 and RPS at 300s
4. **Quality** — baseline vs `eval_after_tuning.json` pass rates
5. **Verdict** — SLO HIT or MISS with gap quantified
6. **Screenshots** — reference `grafana_serving.png`, `grafana_before.png`, `grafana_after.png`

Also update **Agent value** paragraph with H100 eval percentages (replace Path A / local 40% placeholders).

Grading note: **a missed SLO with metric-grounded diagnosis beats a hit you cannot explain.**

---

### Step 9 — Artifact summary

```bash
bash scripts/run_phase7_h100.sh summary
```

Expected Phase 6 additions:

| Artifact | Status after Phase 6 |
|----------|----------------------|
| `results/load_test_h100_baseline.json` | Required |
| `results/load_test_h100_iter*.json` | One per iteration |
| `results/eval_after_tuning.json` | Required — H100 final config |
| `screenshots/grafana_serving.png` | Required — baseline load |
| `screenshots/grafana_before.png` | Required |
| `screenshots/grafana_after.png` | Required |

---

## Phase 6 completion checklist

### H100 / submission (this session)

- [ ] Preflight: vLLM, agent, Grafana, Prometheus, `perf_pool.jsonl` OK
- [ ] Optional smoke load at low RPS completed
- [ ] Baseline: `--rps 10 --duration 300` → `results/load_test_h100_baseline.json`
- [ ] `screenshots/grafana_serving.png` captured during baseline load
- [ ] Diagnosis: which Grafana panel moved first documented
- [ ] 3–4 one-knob iterations with distinct `config_label` / `batch_id`
- [ ] `screenshots/grafana_before.png` / `grafana_after.png` around the meaningful iteration
- [ ] Push-past-SLO run if baseline passed
- [ ] `results/eval_after_tuning.json` on final tuned config
- [ ] `REPORT.md` SLO section filled: baseline, iterations, final numbers, quality, verdict
- [ ] Agent value paragraph updated with H100 eval numbers
- [ ] All reported SLO and eval numbers from **30B H100 self-hosted vLLM only**

### Already done locally (reference only)

- [x] Load driver workflow validated
- [x] Path A iteration: `MAX_ITERATIONS` 3→2, P95 −31% (practice)
- [x] Local vLLM one-knob iteration (KV / waiting queue)
- [x] Tag schema (`run_type=load_test`, `batch_id`, `config_label`)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Mass `timeouts` at 10 RPS | Server saturated or `--timeout` too low | Check vLLM logs; try `--timeout 180`; lower RPS for smoke first |
| `achieved_rps` ≪ `requested_rps` | Driver saturated or agent cannot accept connections | Expected under overload; check agent CPU |
| Grafana flat during load | Metrics not scraped | Prometheus target `vllm` UP; vLLM on `:8000` |
| Agent P95 high, vLLM latency moderate | 2–3 serial LLM calls / revise loops | Langfuse trace-sample; consider `MAX_ITERATIONS` |
| vLLM waiting ↑, KV high | Concurrency / KV limit | Tune `max-num-seqs`, `gpu-memory-utilization`, or `max-model-len` |
| TTFT spikes, decode flat | Prefill-bound | Chunked prefill already on; try `max-num-batched-tokens`, shorter prompts N/A |
| Tuning helps vLLM but not agent P95 | Bottleneck is agent serial work | Agent `MAX_ITERATIONS`, not more vLLM flags |
| vLLM OOM on restart after flag change | Too aggressive memory flags | Reduce `gpu-memory-utilization` or `max-num-seqs` |
| No Langfuse traces for load test | Export dropped under concurrency | `LANGFUSE_DISABLED=1` during load + `trace-sample` after |
| Eval after tuning much worse | Aggressive `MAX_ITERATIONS` cap | Document tradeoff; revert or accept in report |
| Cold start skews first minute | vLLM compile / cache warm | Optional: 1–2 min warmup at 1 RPS before timed run; note in report |

---

## File touch map

| File | Action |
|------|--------|
| `load_test/driver.py` | **Run** — no edits expected |
| `load_test/perf_pool.jsonl` | Read-only |
| `scripts/start_vllm.sh` | **Tune** — one knob per iteration; final config is submission config |
| `scripts/start_vllm_local.sh` | **Do not use on H100** |
| `scripts/run_phase7_h100.sh` | **Run** — `load-baseline`, `load`, `eval-final`, `trace-sample`, `summary` |
| `scripts/phase6_trace_sample.py` | **Run** after load for Langfuse visibility |
| `agent/graph.py` | Optional — `MAX_ITERATIONS` via env; document eval impact |
| `results/load_test_h100_*.json` | **Output** — one file per run |
| `results/eval_after_tuning.json` | **Output** — post-tuning eval (overwrites practice file) |
| `infra/grafana/.../serving.json` | Read during diagnosis |
| `screenshots/grafana_serving.png` | **Capture** during baseline load |
| `screenshots/grafana_before.png`, `grafana_after.png` | **Capture** around key iteration |
| `REPORT.md` | **Fill** SLO section + update Agent value with H100 numbers |
| `_notes/phase6_h100_scratch_log.md` | **Create** — optional iteration table |

---

## Relationship to other phases

| Phase | Dependency on Phase 6 |
|-------|------------------------|
| **1 (vLLM)** | Phase 6 validates Phase 1 flags; iteration log justifies each change in `REPORT.md` |
| **2 (Grafana)** | Primary diagnosis surface — panels must react during 10 RPS load |
| **4 (Langfuse)** | Tags filter slow traces; `trace-sample` after load when export disabled |
| **5 (Evals)** | `eval_baseline.json` (43.3%) vs `eval_after_tuning.json` — did tuning preserve accuracy? |
| **7 (Report)** | **25% SLO diagnosis** — iteration log, before/after evidence, honest hit/miss; polish prose |

Phase 5 showed the verify→revise loop adds only **+3.3 pp** on H100 (40% → 43.3%). That makes `MAX_ITERATIONS=2` a plausible latency knob **if** eval confirms acceptable quality loss — but measure on H100, not Path A alone.

---

## Time budget (single H100 session)

| Block | Duration | Notes |
|-------|----------|-------|
| Preflight + Grafana layout | 5–10 min | Stack should already be up from Phase 5 |
| Smoke load (optional) | 2–3 min | 2 RPS × 60s |
| Baseline load 10 RPS × 300s | ~8–12 min | + drain up to 600s if many in-flight |
| Grafana `grafana_serving.png` | 2 min | During baseline |
| Diagnosis + hypothesis | 10–15 min | Dashboard + jq + optional trace-sample |
| Per iteration (change + re-run + compare) | ~15–25 min | × 3–4 iterations |
| Before/after screenshots | 5 min | Mid-run captures |
| Push-past run (if pass) | 5–10 min | 12–15 RPS × 120s |
| Final eval (30 Q) | ~45–60 min | Sequential; same as Phase 5 |
| Fill `REPORT.md` SLO section | 15–20 min | Numbers + iteration log + verdict |
| **Total** | **~2.5–4 h** | Assumes vLLM warm; add restarts per iteration |

If slot time is tight: run baseline + 2 iterations + eval in-session; document a third iteration plan in scratch log only if you must defer — but submission expects 3–4 grounded iterations.

---

## Next phase

**Phase 7 (Docs)** — consolidate `REPORT.md` (≤3 pages): serving config table, baseline eval, SLO iteration log, agent value paragraph, specific "what I'd do with more time." Remove or shrink appendix practice sections. See [README Phase 7](../README.md#phase-7-docs) and [`_local_dev/phase_7_plan.md`](_local_dev/phase_7_plan.md).
