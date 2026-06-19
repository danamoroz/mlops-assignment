# Phase 6 Plan — Local Test Environment

This plan adapts [README.md Phase 6 (SLOs)](../README.md#phase-6-slos) for **local development on your machine** (WSL2 / laptop), not the cloud H100 VM. Per [assignment_remarks.md](assignment_remarks.md): practice the load-test + diagnosis workflow locally first; **submission artifacts** (SLO numbers for `REPORT.md`, `screenshots/grafana_before.png` / `grafana_after.png`, `results/eval_after_tuning.json` from the tuned 30B config) must come from the H100 run later.

---

## Goal

By the end of Phase 6 **locally** you should have:

- Run `load_test/driver.py` end-to-end against the agent while watching Grafana
- A **baseline load-test JSON** (`results/load_test.json` or named variants) with P50/P95/P99 agent latency and achieved RPS
- At least **one deliberate tuning iteration** documented in the form *"saw X → hypothesized Y → changed Z → result was W"* (even if the local SLO is nowhere near reachable)
- Confidence reading which dashboard panel moves first under load (queue vs TTFT vs KV cache vs agent-side queueing)
- Langfuse traces filterable by `run_type=load_test` and `batch_id` for slow-request drill-down
- A draft **quality check** workflow: re-run eval after a config change → `results/eval_after_tuning.json` (local numbers are directional only)

**Final submission quality** (H100 only):

- Hit or miss the real platform SLO with quantified gap
- 3–4 metric-grounded tuning iterations in `REPORT.md`
- Before/after Grafana pair around the change that moved the needle
- `results/eval_after_tuning.json` from the **final H100 config** — compare to `results/eval_baseline.json`
- Honest verdict: SLO hit, or missed with diagnosis (25% of grade: diagnosis quality > green checkmark)

---

## The SLO (what you are measuring)

From Phase 1 / README — this is **end-to-end agent latency**, not raw vLLM latency alone:

> **P95 end-to-end agent latency under 5 seconds, 10+ RPS (1 RPS = 1 full agent run per second) over a 5-minute window.**

| Dimension | Meaning |
|-----------|---------|
| **End-to-end** | Wall clock from `POST /answer` to full response — includes 2–3 LLM calls (generate → verify → optional revise), SQLite execution, and Python overhead |
| **P95** | 95th percentile of successful request latencies during the window |
| **10+ RPS** | Sustained offered load: driver fires ≥10 new agent requests per second for 300 seconds (~3000 total) |
| **5-minute window** | `--duration 300` on the load driver |

**Pass criteria (H100):** `latency_p95 < 5.0` **and** `requested_rps >= 10` **and** low timeout/error rate (driver summary: `ok / total_requests` should be near 1.0).

Locally on a 0.6B stand-in or low-end GPU you will **not** meet this SLO. That is expected. The local phase teaches **how to run the test, read the dashboard, form hypotheses, change one knob, and verify the targeted metric moved**.

---

## What you are building (context)

Phase 6 closes the loop between Phase 1 serving config and real concurrent traffic. The load driver hits the **agent**, not vLLM directly — vLLM metrics explain *why* agent latency moved.

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
  results/load_test.json  (summary: p50/p95/p99, achieved_rps, errors)
        │
        ├── Grafana serving.json  ──► vLLM latency, throughput, KV cache
        └── Langfuse  ──► filter run_type=load_test, batch_id=...
```

### Load driver (already implemented)

| Flag | Default | Purpose |
|------|---------|---------|
| `--rps` | `8.0` | Target requests/sec (use `10` on H100 for SLO attempt) |
| `--duration` | `300` | Seconds to drive load |
| `--agent-url` | `http://localhost:8001/answer` | Agent endpoint |
| `--batch-id` | auto `load-<timestamp>` | Langfuse filter for this run |
| `--config-label` | none | Tag traces to vLLM config iteration (e.g. `h100-30b-baseline`) |
| `--out` | `results/load_test.json` | JSON output |

Each request sends Langfuse tags:

```python
{
  "run_type": "load_test",
  "source": "load_driver",
  "db_id": "<from question>",
  "batch_id": "<batch>",
  "seq": "<request index>",
  "config_label": "<optional>",
}
```

Use distinct `batch_id` and `config_label` per tuning iteration so traces do not mix.

### Grafana panels to watch (from `serving.json`)

| Panel group | What it tells you | Moves first when… |
|-------------|-------------------|-------------------|
| **Time to first token (percentiles)** | Prefill / queue delay before generation starts | Prompt too long, batch queue full, GPU saturated on prefill |
| **End-to-end request latency (percentiles)** | Total vLLM request time per LLM call | Any bottleneck in the inference path |
| **Prefill vs decode (p95)** | Whether slowness is input processing or token generation | Long schemas → prefill; short outputs → often prefill-bound per call |
| **Queue & inter-token latency (p95)** | Scheduler backlog, decode smoothness | `max-num-seqs` too low, KV cache full, too many concurrent seqs |
| **Request concurrency** (running / waiting) | How backed up vLLM is | Waiting ↑ → concurrency or KV limit hit before raw compute |
| **Token throughput** | Actual generation rate | Flat under rising load → saturated |
| **GPU KV cache usage** | Headroom for more concurrent requests | High usage + waiting queue → need more KV memory or fewer/l shorter seqs |
| **Preemptions & queue depth** | Scheduler evicting/reordering | KV pressure; latency variance spikes |

**Agent-side signals** (not on vLLM dashboard — use driver JSON + Langfuse):

- P95 agent latency >> P95 vLLM e2e → multiple serial LLM calls or revise loops dominating
- Timeouts in driver summary → agent or vLLM cannot keep up with offered RPS
- Langfuse waterfall: 3 LLM spans per request vs 2 → revise fired; compare slow traces

---

## Local vs H100 (what changes)

| README (VM / H100) | Local test phase |
|---|---|
| SLO: P95 &lt; 5s at 10+ RPS for 300s | Same **commands**; expect P95 in tens of seconds and RPS &lt;&lt; 10 on stand-in model |
| Tune `scripts/start_vllm.sh` for 30B MoE | Tune `scripts/start_vllm_local.sh` **only to practice one-knob iteration** — numbers are not submission-worthy |
| `screenshots/grafana_before.png` / `after.png` | Capture locally to learn framing; **re-capture on H100** around the iteration that mattered |
| SLO numbers in `REPORT.md` | Directional locally; report **30B H100 numbers** only |
| `results/eval_after_tuning.json` | Run locally to verify harness; **commit H100 run** after final tuned config |

**Local success looks like:** you can run a 2–5 minute load test, point at a Grafana panel that moved, write one honest iteration line, and know which H100 knobs you will try first — not that you hit 10 RPS / 5s P95.

---

## Path A — Hosted API (Nebius / OpenAI-compatible, no local vLLM)

Use this when your machine cannot run vLLM (weak GPU, no CUDA). Same agent + load driver + Langfuse workflow; **Grafana vLLM panels stay flat** because there is no local `/metrics` endpoint.

### Setup (`.env`)

Uncomment/fill the Path A block in `.env.example`:

```bash
VLLM_BASE_URL=https://api.tokenfactory.nebius.com/v1
VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507
NEBIUS_API_KEY=...
```

Get a key at [Nebius Token Factory](https://tokenfactory.nebius.com). The agent reads `NEBIUS_API_KEY` via `agent/graph.py` (same as Phase 4 Path A).

### One-command workflow

Run **one step at a time** — keep the agent in a separate terminal (do not let a script restart it mid-run):

```bash
# Terminal 1 — agent (you control MAX_ITERATIONS here)
set -a && source .env && set +a
export OPENAI_API_KEY="${NEBIUS_API_KEY:-$OPENAI_API_KEY}"
MAX_ITERATIONS=3 uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001

# Terminal 2 — load / eval steps
bash scripts/run_phase6_path_a.sh load-baseline --duration=60
# restart agent with MAX_ITERATIONS=2, then:
bash scripts/run_phase6_path_a.sh load-tuned --duration=60
bash scripts/run_phase6_path_a.sh eval
```

The script does **not** start/stop uvicorn. That avoids the failure mode where a long load test gets interrupted or the agent is killed by a trap on exit.

### Langfuse traces (`run_type=load_test`, distinct `batch_id`)

The load driver already sends these tags on every request. Local Langfuse often **drops spans under concurrent load** (`Failed to export span batch` in agent logs). Use a **two-step** approach:

| Step | Agent | Command |
|------|-------|---------|
| Load test | `LANGFUSE_DISABLED=1` | `bash scripts/run_phase6_path_a.sh load-baseline` |
| Trace sample | Langfuse **on** (no `LANGFUSE_DISABLED`) | `bash scripts/run_phase6_path_a.sh trace-sample nebius-baseline-120s nebius-30b-baseline` |

The trace sample fires **5 sequential** requests with the same `run_type=load_test` / `batch_id` tags — enough for Langfuse UI visibility without overloading the stack. Wait ~30s, then filter in http://localhost:3001 → Tracing → Metadata: `run_type` = `load_test`, `batch_id` = your batch.

Use a **different `batch_id`** per tuning iteration (e.g. `nebius-iter-maxiter2-traces` after the MAX_ITERATIONS=2 run).

### Path A vs local vLLM vs H100

| | Path A (Nebius) | Local vLLM | H100 (submission) |
|---|---|---|---|
| Model | 30B via API | 0.6B stand-in | 30B self-hosted |
| Grafana vLLM panels | **N/A** | Yes | Yes |
| Diagnosis | Langfuse + load JSON | Grafana + Langfuse | Grafana + Langfuse |
| Tuning knobs | Agent (`MAX_ITERATIONS`), timeouts | vLLM flags + agent | vLLM flags + agent |
| Offered RPS | 1–2 (API cost / latency) | 1–4 | 10+ |
| SLO numbers for `REPORT.md` | Practice only | Practice only | **Submit these** |
| Screenshots | Langfuse traces; defer Grafana to H100 | Local practice | Required |

### Path A diagnosis (no Grafana)

1. **`results/load_test_*.json`** — `latency_p95`, `ok/total`, `timeouts`, `achieved_rps`
2. **Langfuse** — filter `run_type=load_test`, sort by duration; count LLM spans per trace (`generate_sql`, `verify`, `revise`)
3. **Compare iterations** — e.g. baseline `config_label=nebius-30b-baseline` vs tuned `nebius-30b-maxiter2`

Example iteration line (Path A):

> *"saw agent P95 22s with 3 LLM spans on slow traces → hypothesized revise loop adds serial API latency → changed MAX_ITERATIONS 3→2 → P95 dropped to 15s, ok rate unchanged, eval pass rate flat"*

### Path A prerequisites

- [x] Path A block in `.env` with valid `NEBIUS_API_KEY`
- [x] Phase 3 agent wired; Phase 4 Langfuse tags
- [x] Phase 5 `results/eval_baseline.json` (re-run on Nebius if prior baseline used a different backend)
- [ ] **Do not** start `start_vllm_local.sh` — agent talks to Nebius directly

Preflight:

```bash
set -a && source .env && set +a
export OPENAI_API_KEY="${NEBIUS_API_KEY:-$OPENAI_API_KEY}"
curl -s "$VLLM_BASE_URL/models" -H "Authorization: Bearer $OPENAI_API_KEY" | jq -r '.data[0].id'
curl -s http://localhost:8001/health | jq .   # after starting agent
```

---

## Prerequisites (local)

Assumes prior local milestones:

- [x] Phase 0 — `load_test/perf_pool.jsonl` present, Grafana at http://localhost:3000
- [x] Phase 1 — vLLM stand-in running (`scripts/start_vllm_local.sh`), `/metrics` scraped
- [x] Phase 2 — `serving.json` dashboard with latency / throughput / KV panels reacting under load
- [x] Phase 3 — agent on `:8001`, verify+revise loop wired
- [x] Phase 4 — Langfuse tags working (`run_type`, `batch_id`, `config_label`)
- [x] Phase 5 — `results/eval_baseline.json` exists (local stand-in pass rates OK)

Quick preflight:

```bash
curl -s http://localhost:8001/health | jq .
curl -s http://localhost:8000/health | jq .    # or /v1/models
docker compose ps | grep -E 'grafana|prometheus|langfuse'
wc -l load_test/perf_pool.jsonl                 # expect 1500
```

Stack should be running in **three terminals** (or tmux panes):

1. vLLM — `bash scripts/start_vllm_local.sh`
2. Agent — `uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001`
3. Observability — `docker compose up -d` (Grafana :3000, Langfuse :3001)

---

## Step-by-step (local)

### Step 0 — Set up iteration tracking

Create a scratch section in `REPORT.md` (or a local notes file) before the first run:

```markdown
## Phase 6 — SLO tuning (draft)

### Platform SLO
P95 agent latency < 5s, 10+ RPS, 300s window.

### Baseline (local stand-in)
- config: start_vllm_local.sh defaults, config_label=local-0.6b-baseline
- load: `--rps N --duration D`
- result: p95=?, achieved_rps=?, ok_rate=?

### Iterations
1. saw … → hypothesized … → changed … → result …
```

On H100, rename labels (`h100-30b-baseline`, `h100-30b-iter1`, …) and replace local numbers.

---

### Step 1 — Open Grafana and Langfuse before load

1. **Grafana** — http://localhost:3000 → **vLLM serving** dashboard
2. Time range: **Last 15 minutes**, refresh **5s**
3. Arrange panels: **e2e latency p95**, **TTFT p95**, **running/waiting**, **KV cache usage** visible at once
4. **Langfuse** — http://localhost:3001 → Traces → note filter: `run_type = load_test`

Keep both tabs open for every run in this phase.

---

### Step 2 — Baseline load test (local smoke scale)

Start with a **short, low-RPS** run to validate the pipeline without a 45-minute wait:

```bash
cd /home/danar/repos/ai_performance/mlops/hw2_llm_inference_o11y

uv run python load_test/driver.py \
  --rps 2 \
  --duration 120 \
  --batch-id local-baseline-smoke \
  --config-label local-0.6b-baseline \
  --out results/load_test_baseline_smoke.json
```

Watch Grafana during the run. Confirm panels move (latency, concurrency, KV).

Then run a **longer local baseline** at the highest RPS your machine sustains without mass timeouts (often 1–4 RPS on CPU/small GPU):

```bash
uv run python load_test/driver.py \
  --rps 3 \
  --duration 300 \
  --batch-id local-baseline-300s \
  --config-label local-0.6b-baseline \
  --out results/load_test_baseline.json
```

Inspect summary:

```bash
jq '.summary' results/load_test_baseline.json
```

Record in notes:

| Field | Your value | SLO target |
|-------|------------|------------|
| `latency_p95` | ? | &lt; 5.0 s |
| `requested_rps` | ? | ≥ 10 |
| `achieved_rps` | ? | close to requested |
| `ok / total_requests` | ? | ~100% |
| `timeouts` | ? | 0 |

**README step 2 (local interpretation):** even if you "miss" immediately, run one iteration at **higher** RPS (e.g. double `--rps`) until timeouts or queue depth spike — learn **what breaks first** on your dashboard.

---

### Step 3 — Diagnose (do not guess fixes yet)

While baseline (or overload) run is visible on Grafana, answer:

1. **Which panel moved first** as load increased?
2. **Where is time spent?** Compare TTFT vs e2e on vLLM panels; open a slow Langfuse trace (`batch_id=local-baseline-300s`, sort by latency) and count LLM spans.
3. **Hypothesis in one sentence** tied to a metric, e.g.:
   - *"`num_requests_waiting` climbed to 8 while KV cache hit 90% → concurrency limited by KV headroom, not compute."*
   - *"Agent P95 45s but vLLM e2e p95 8s → ~3 serial LLM calls per request dominate; serving tuning alone won't fix."*
   - *"TTFT p95 spiked, decode flat → prefill-bound on long schema prompts."*

Use Langfuse for agent-side breakdown:

- Filter: `run_type = load_test`, `batch_id = local-baseline-300s`
- Sort by duration; inspect `generate_sql` / `verify` / `revise` span times
- Compare `db_id` tags if some databases have larger schemas

**Do not change config until you can point at a dashboard panel or trace.**

---

### Step 4 — Change one thing, re-run, confirm metric moved

Pick **one** lever per iteration. Examples for **local practice** (map to H100 equivalents in notes):

| Local change (one at a time) | Target metric | H100 analogue |
|------------------------------|---------------|---------------|
| `--max-num-seqs 4 → 2` | KV usage ↓, waiting ↑ or latency ↓ | Same — trade concurrency vs latency |
| `--max-num-seqs 4 → 8` (if VRAM allows) | waiting ↓, throughput ↑ | Primary SLO knob on H100 |
| `--max-model-len 4096 → 2048` | KV usage ↓ | Free KV blocks for more seqs |
| `--gpu-memory-utilization 0.70 → 0.85` | KV headroom ↑ | More concurrent requests |
| Agent: lower `MAX_ITERATIONS` in `graph.py` | Agent P95 ↓, quality may ↓ | Cost/latency vs eval pass rate tradeoff |

After editing `scripts/start_vllm_local.sh` (or agent cap):

1. **Restart vLLM** (and agent if graph changed)
2. Update `--config-label` (e.g. `local-0.6b-maxseqs-2`)
3. Re-run the **same** load command (same `--rps`, `--duration`, new `--batch-id`)
4. Compare `jq '.summary'` before vs after
5. Confirm the **targeted Grafana panel** moved in the expected direction
6. Ask: **did agent P95 move with it?** (sometimes vLLM improves but agent SLO does not — document that)

Write one line:

> *"saw KV cache pegged at 95% and waiting queue at 6 → hypothesized max-num-seqs too high for VRAM → changed max-num-seqs 4→2 → KV dropped to 60% but P95 agent latency worsened because throughput fell"*

That is a valid iteration — negative results count.

**Screenshot (local practice):** capture Grafana mid-run for baseline and for the iteration you care about. Submission needs `screenshots/grafana_before.png` and `screenshots/grafana_after.png` from **H100** around the iteration that moved the needle.

---

### Step 5 — Iterate (3–4 rounds on H100; 1–2 locally)

README expects **3–4 iterations** on the VM. Locally, do **at least one** full diagnose → change → re-measure cycle so the workflow is muscle memory.

Each iteration produces:

- [ ] One line in `REPORT.md` (*saw → hypothesized → changed → result*)
- [ ] `results/load_test_<label>.json` saved
- [ ] Grafana observation (screenshot optional locally)
- [ ] Langfuse check: new `batch_id`, slow traces still inspectable

**Stop guessing:** if you are on iteration 7 without a metric that moved, re-read the dashboard and Langfuse — do not stack random flags.

---

### Step 6 — Push past the SLO (H100; optional locally)

If you **hit** the SLO on H100 on the first try, README still wants you to **increase load until something breaks** (e.g. `--rps 12`, then 15) and document what fails first. Locally, simulate by raising `--rps` until `timeouts` &gt; 0 or `achieved_rps` plateaus.

---

### Step 7 — Final config + eval quality check

After your **final H100 tuned config** (local: after last local iteration for harness practice):

```bash
# H100 example — use your final config_label
uv run python evals/run_eval.py \
  --out results/eval_after_tuning.json
```

Compare to baseline:

```bash
jq '{baseline: .summary.final_pass_rate, tuned: .}' results/eval_baseline.json  # baseline
jq '.summary' results/eval_after_tuning.json
```

If tuning regressed quality (lower `final_pass_rate` or flat `pass_rate_by_iteration`), that belongs in the writeup — latency wins that destroy accuracy are a real tradeoff.

**Local:** run on stand-in model only to confirm the command and JSON shape; **commit H100 `eval_after_tuning.json`** for submission.

---

### Step 8 — Document in `REPORT.md`

Phase 6 section should include:

1. **Baseline vs SLO** — table with p95, RPS, error rate, pass/fail
2. **Iteration log** — all *saw → hypothesized → changed → result* lines
3. **Final numbers** — best achieved p95 and RPS at 300s
4. **Quality** — `eval_baseline.json` vs `eval_after_tuning.json` pass rates
5. **Verdict** — SLO hit, or missed with gap quantified (e.g. *"P95 6.2s at 10 RPS — miss by 1.2s; KV cache saturation"*)
6. **Before/after** — reference `screenshots/grafana_before.png` and `grafana_after.png`

Grading note: **a missed SLO with metric-grounded diagnosis beats a hit you cannot explain.**

---

## Suggested H100 tuning order (for VM session)

When you move to the H100, try knobs in an order that matches common bottlenecks for this workload (short outputs, 2–3 calls, ~2K prompt tokens):

1. **`--max-num-seqs`** — primary concurrency vs latency tradeoff for 10+ RPS
2. **`--gpu-memory-utilization`** — KV cache headroom (after model weights)
3. **`--max-model-len`** — don't over-reserve; schema + output fits in ~4K
4. **Quantization / dtype** — if 30B + KV doesn't fit comfortably at desired concurrency
5. **`--max-num-batched-tokens`** — throughput under mixed prefill/decode
6. **Prefix caching** — repeated schema tokens across generate/verify/revise
7. **Chunked prefill** — if TTFT dominates on long schemas
8. **Agent `MAX_ITERATIONS`** — only after serving is sane; measure eval impact

Fill `scripts/start_vllm.sh` and the H100 table in `REPORT.md` as you go. Keep `start_vllm_local.sh` for local dev only.

---

## Phase 6 completion checklist

### Local test phase (now)

- [ ] Preflight: agent, vLLM, Grafana, Langfuse, `perf_pool.jsonl` OK
- [ ] Baseline load test completed; `results/load_test_baseline.json` (or smoke variant) saved
- [ ] Grafana panels identified that move under load (latency, queue, KV)
- [ ] Langfuse traces visible with `run_type=load_test` and distinct `batch_id`
- [ ] At least one metric-grounded hypothesis written down
- [ ] At least one **one-knob** iteration: config change → re-run → compare summary JSON
- [ ] One iteration line in *saw → hypothesized → changed → result* format
- [ ] Optional: `eval_after_tuning.json` on local stand-in to verify eval harness post-tuning
- [ ] Know which H100 flags you will try first and what panel will prove they worked

### H100 / submission (later)

- [ ] `scripts/start_vllm.sh` tuned for `Qwen/Qwen3-30B-A3B-Instruct-2507`
- [ ] `.env` → `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`
- [ ] Baseline: `uv run python load_test/driver.py --rps 10 --duration 300 --config-label h100-30b-baseline --out results/load_test_h100_baseline.json`
- [ ] 3–4 tuning iterations with distinct `config_label` / `batch_id`
- [ ] Push-past-SLO run if baseline already passes (document what breaks)
- [ ] `screenshots/grafana_before.png` and `screenshots/grafana_after.png` from the meaningful iteration
- [ ] `uv run python evals/run_eval.py --out results/eval_after_tuning.json` on final config
- [ ] `REPORT.md` Phase 6: baseline, iterations, final numbers, quality comparison, honest verdict
- [ ] All reported SLO and eval numbers from 30B H100 only

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `perf_pool.jsonl not found` | Data not loaded | `uv run python scripts/load_data.py` |
| Connection refused on `:8001` | Agent down | Start uvicorn |
| Mass `timeouts` in driver | RPS too high for hardware | Lower `--rps`; check vLLM OOM logs |
| `achieved_rps` ≪ `requested_rps` | Server saturated; requests queue | Expected under overload; reduce RPS for clean baseline |
| Grafana flat during load | vLLM metrics not scraped | Prometheus target `vllm` UP; vLLM on `:8000` |
| Agent P95 high, vLLM latency moderate | Multiple LLM calls / revise loops | Langfuse trace waterfall; consider agent iteration cap |
| vLLM waiting ↑, KV high | Concurrency / KV limit | Reduce `max-num-seqs` or increase KV headroom (`gpu-memory-utilization`, shorter `max-model-len`) |
| TTFT spikes, decode flat | Prefill-bound | Chunked prefill, prefix caching, smaller prompts |
| Tuning helps vLLM but not agent P95 | Bottleneck is agent serial work, not single-call inference | Agent architecture / iteration count, not more vLLM flags |
| No Langfuse traces for load test | Keys missing or tags not sent | Check `.env`; confirm driver sends `tags` in payload |
| Eval after tuning much worse | Aggressive latency tuning (iter cap, weaker verify) | Document tradeoff; revert knob or accept in report |
| Local numbers "absurd" vs SLO | Stand-in model / hardware | Expected — do not put local p95 in final `REPORT.md` |

---

## File touch map

| File | Action |
|------|--------|
| `load_test/driver.py` | **Run** — already implements async load + tags + summary JSON |
| `load_test/perf_pool.jsonl` | Read-only — question pool for load test |
| `scripts/start_vllm_local.sh` | **Tune locally** (one knob per iteration) for practice |
| `scripts/start_vllm.sh` | **Tune on H100** — submission serving config |
| `agent/graph.py` | Optional — `MAX_ITERATIONS` latency vs quality tradeoff (document eval impact) |
| `results/load_test*.json` | **Output** — one file per run or iteration |
| `results/eval_after_tuning.json` | **Output** — post-tuning eval (H100 for submission) |
| `infra/grafana/.../serving.json` | Read during diagnosis; panels must react under load |
| `screenshots/grafana_before.png`, `grafana_after.png` | Capture on H100 around key iteration |
| `REPORT.md` | **Iteration log**, baseline/final numbers, verdict (finalize Phase 7) |

---

## Relationship to other phases

| Phase | Dependency on Phase 6 |
|-------|------------------------|
| **1 (vLLM)** | Phase 6 validates the flags you chose; iteration log justifies each flag in `REPORT.md` |
| **2 (Grafana)** | Primary diagnosis surface — latency, throughput, KV panels must react during load test |
| **4 (Langfuse)** | Tags (`run_type=load_test`, `batch_id`, `config_label`) filter slow traces under load |
| **5 (Evals)** | `eval_baseline.json` vs `eval_after_tuning.json` — did tuning preserve execution accuracy? |
| **7 (Report)** | **25% SLO diagnosis** — iteration log, before/after evidence, honest hit/miss |

Current local baseline eval (stand-in model): `final_pass_rate ≈ 0.40`, flat across iterations — loop not lifting quality locally. Phase 6 tuning may still change latency; re-check eval after tuning on **H100** where the loop and model are representative.

---

## Next phase

**Phase 7 (Docs)** — consolidate `REPORT.md` (≤3 pages): serving config, baseline eval, SLO iteration log, agent value paragraph, specific "what I'd do with more time." See [README Phase 7](../README.md#phase-7-docs).
