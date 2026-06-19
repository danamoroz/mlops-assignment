# Phase 2 Plan — Nebius H100 VM (Final / Submission Environment)

This plan adapts [README.md Phase 2 (o11y core)](../README.md#phase-2-o11y-core) for the **Nebius H100 slot**. It builds on what we already validated locally in [`_local_dev/phase_2_plan.md`](_local_dev/phase_2_plan.md). Local Phase 2 dashboard work is done in `infra/grafana/provisioning/dashboards/serving.json`; this session **re-verifies every panel against 30B metrics**, runs a meaningful burst, and produces the submission screenshot.

Per [assignment_remarks.md](_local_dev/assignment_remarks.md): build and wire the Grafana dashboard locally first; reserve the H100 for submission-quality load and `screenshots/grafana_serving.png`.

---

## Goal

By the end of Phase 2 on Nebius you should have:

- Grafana **vLLM serving** dashboard covering **latency**, **throughput**, and **KV cache** health
- Every panel visibly reacting during a burst against **`Qwen/Qwen3-30B-A3B-Instruct-2507`**
- Dashboard JSON committed under `infra/grafana/provisioning/dashboards/serving.json` (already built locally — re-verify, tweak only if H100 metrics differ)
- Submission screenshot at **`screenshots/grafana_serving.png`** ([CAPTURE.md](../screenshots/CAPTURE.md))

**Out of scope for Phase 2** (later phases): agent server on `:8001`, Langfuse traces (Phase 4), eval pass rates (Phase 5), full 5-minute SLO load test (Phase 6). Phase 2 only needs a **burst** that makes panels move — not 10 RPS × 5 minutes.

---

## What you are building (context)

Phase 2 is **serving-layer observability**. A teammate should open the dashboard during a load test and answer:

1. **Is the system slow?** If yes, **where** in the request lifecycle (queue → prefill → decode → e2e)?
2. **Is throughput keeping up?** Tokens out, requests served, queue depth, generation rate.
3. **Do we have KV cache headroom?** Or are we about to preempt / evict?

The assignment deliberately does **not** name every metric. Local work explored `/metrics` and mapped metrics to these questions. On H100 you **validate** those choices at 30B scale and capture the artifact.

---

## What we already have locally (don't re-invent)

Validated on WSL2 / T500 (2026-06), per [`phase_2_plan.md`](_local_dev/phase_2_plan.md):

| Item | Local status | On Nebius |
|------|--------------|-----------|
| Dashboard JSON | Full layout in `serving.json` — 3 rows, 13 panels | **Load as-is**; fix queries only if metrics missing |
| Latency panels | TTFT, E2E, prefill vs decode, queue + inter-token (p50/p95/p99 or p95) | Re-verify percentiles populate under 30B load |
| Throughput panels | Running/waiting, gen + prompt tok/s, success/s, output length p50/p95 | Expect **much higher** absolute rates on H100 |
| KV cache panels | `gpu_cache_usage_perc`, stat gauge, preemptions/s + waiting | Primary headroom signal for Phase 1 `--max-num-seqs` tuning |
| Burst harness | `scripts/burst_vllm_load.sh` (parallel / sustained / kv-pressure) | **Same script** against 30B |
| Prometheus scrape | `host.docker.internal:8000/metrics` every 5s | Same wiring |
| Grafana provisioning | Auto-load from `infra/grafana/provisioning/` | Restart Grafana after JSON edits |

### Dashboard layout (committed)

```
┌─────────────────────────────────────────────────────────────────┐
│  ROW: Latency                                                   │
│  [ TTFT p50/p95/p99 ] [ E2E p50/p95/p99 ]                       │
│  [ Prefill vs decode p95 ] [ Queue + inter-token p95 ]          │
├─────────────────────────────────────────────────────────────────┤
│  ROW: Throughput                                                │
│  [ Running / waiting ] [ Gen + prompt tok/s ] [ Success/s ]     │
│  [ Output length p50/p95 ]                                      │
├─────────────────────────────────────────────────────────────────┤
│  ROW: KV cache & scheduler pressure                             │
│  [ GPU KV cache % ] [ KV stat (now) ] [ Preemptions + waiting ] │
└─────────────────────────────────────────────────────────────────┘
```

Refresh **5s**, default range **Last 15 minutes** — already set in `serving.json`.

### Metric name note (local plan vs committed JSON)

The local plan references `vllm:kv_cache_usage_perc`; the committed dashboard uses **`vllm:gpu_cache_usage_perc`**, which is what vLLM 0.10.x exposes on H100. Both `gpu_cache_usage_perc` and `kv_cache_usage_perc` appear in `/metrics` on this build — the dashboard targets the GPU gauge. No rename needed unless you prefer the alias.

---

## Local vs Nebius (what changes)

| Local test (WSL / 0.6B CPU) | Nebius H100 VM |
|-----------------------------|----------------|
| Panel **wiring** validation | Panel **behavior** at real serving scale |
| Percentiles noisy / meaningless | First trustworthy TTFT, E2E, prefill/decode splits |
| KV cache may stay low unless forced | KV fills meaningfully at `--max-num-seqs 32` under burst |
| Optional draft screenshot | **Required** `screenshots/grafana_serving.png` |
| `VLLM_MODEL=Qwen/Qwen3-0.6B` | **`Qwen/Qwen3-30B-A3B-Instruct-2507`** (from `.env`) |

**Do not rebuild the dashboard from scratch on H100** unless a panel shows "No data" — fix individual PromQL queries, don't redesign layout.

---

## Prerequisites (Nebius VM)

Confirm before opening Grafana (most come from [Phase 0](final_phase_0.md) + [Phase 1](final_phase_1.md)):

- [x] **Phase 1 complete** — 30B vLLM on `:8000`, Prometheus target `vllm` **UP**
- [x] **`docker compose up -d`** — Prometheus + Grafana healthy
- [x] **`.env`** — `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, Path A overrides commented out
- [ ] **Port forwards** — `:3000` (Grafana), `:9090` (Prometheus) from laptop if capturing screenshot remotely
- [ ] **`screenshots/`** directory exists — `mkdir -p screenshots`

**VM sanity (current session):** H100 80GB detected, vLLM listening on `:8000`, Grafana `:3000`, Prometheus `:9090`, scrape target **UP**. All histogram/counter names used in `serving.json` present in `/metrics`.

---

## Execution steps

### Step 0 — Confirm the metrics pipeline

With vLLM and compose running:

```bash
cd ~/mlops-assignment

# Raw metrics from 30B vLLM
curl -s http://localhost:8000/metrics | grep '^vllm:' | sed 's/{.*//' | sort -u

# Prometheus target
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="vllm") | {health, lastError}'

# One probe to seed counters
bash scripts/probe_vllm_sql.sh
```

Open:

- http://localhost:9090/targets — job `vllm` = **UP**
- http://localhost:9090/graph — try `vllm:generation_tokens_total`; value should increase after probe

---

### Step 1 — Load the dashboard

```bash
# Pick up latest serving.json from git pull / local edits
docker compose restart grafana
```

Open http://localhost:3000 (`admin` / `admin`) → **Dashboards** → **vLLM serving**.

Confirm all three rows render without "No data" at idle (some latency percentiles may be empty until traffic — that's OK).

If Grafana shows an **older** 2-panel starter dashboard, the provisioned JSON did not reload — export from UI or confirm file path `infra/grafana/provisioning/dashboards/serving.json`, then restart Grafana again.

---

### Step 2 — Validate PromQL on H100 (before trusting panels)

In Prometheus → Graph, spot-check the queries that drive each category:

| Category | Test query |
|----------|------------|
| Latency | `histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))` |
| Throughput | `rate(vllm:generation_tokens_total[1m])` |
| KV cache | `vllm:gpu_cache_usage_perc` |

If any query returns empty **after** a burst (Step 3), check metric name in `/metrics` dump — do not guess from docs alone.

**Prefix cache (optional enhancement):** H100 exposes `gpu_prefix_cache_hits_total` / `gpu_prefix_cache_queries_total` (prefix caching enabled in `start_vllm.sh`). Not required for Phase 2 acceptance; add a hit-rate panel in Phase 6 if prefix caching becomes a tuning lever.

---

### Step 3 — Burst load: make every panel react

Use the repo burst harness (same as local plan):

```bash
# Terminal 2 — keep Grafana open on :3000, refresh 5s, range "Last 15 minutes"

# Quick parallel burst (latency + throughput)
bash scripts/burst_vllm_load.sh parallel

# KV cache pressure (long outputs, 8 concurrent)
bash scripts/burst_vllm_load.sh kv-pressure

# Or combined
bash scripts/burst_vllm_load.sh all

# Better percentile signal (~2 min sustained)
bash scripts/burst_vllm_load.sh sustained
```

**Verification checklist** while watching Grafana:

| Category | Expect during burst on 30B |
|----------|----------------------------|
| **Latency** | TTFT / E2E / prefill-decode lines move; p95 may be sub-second on H100 — still visible |
| **Throughput** | `running` / `waiting` > 0; gen + prompt tok/s spike; success/s rises |
| **KV cache** | `gpu_cache_usage_perc` climbs; stat panel changes color if >70%; preemptions/s may stay 0 unless you push concurrency hard |

If a panel stays flat:

1. Run its exact PromQL in Prometheus Graph during the burst
2. Fix query in `serving.json` (or Grafana UI → export JSON)
3. `docker compose restart grafana` and re-test

**Stronger KV pressure** (if cache panel barely moves):

- Temporarily lower `--max-num-seqs` in `start_vllm.sh` (e.g. 8), restart vLLM, re-run `kv-pressure`
- Or increase parallel count in `burst_vllm_load.sh` / raise `max_tokens`

Restore Phase 1 production flags after the test unless you intentionally keep a lower concurrency for Phase 3.

---

### Step 4 — Capture submission screenshot

Required artifact: **`screenshots/grafana_serving.png`**

Capture **during or immediately after** `bash scripts/burst_vllm_load.sh sustained` or `all`:

- Time range covers the burst window (**Last 15 minutes**)
- **All three rows** visible in one frame (zoom browser to ~90%, or scroll-stitch)
- Multiple panels show clear activity — not flat idle lines
- Dashboard title **vLLM serving** visible

```bash
mkdir -p screenshots
# Cursor screenshot, browser capture, or scrot on VM with X forwarding
```

See [screenshots/CAPTURE.md](../screenshots/CAPTURE.md). This is the same frame reused in Phase 6 if you run a longer load test later — Phase 2 only requires *a* burst with reacting panels.

---

### Step 5 — Commit dashboard JSON (if changed)

If you edited panels on H100:

1. Dashboard settings → **JSON Model** → save to `infra/grafana/provisioning/dashboards/serving.json`
2. Confirm clean reload:

```bash
docker compose restart grafana
# open http://localhost:3000 — all panels appear without manual import
```

**Do not commit** Grafana admin password changes or datasource overrides — only dashboard JSON under `infra/grafana/provisioning/dashboards/`.

No `REPORT.md` section required for Phase 2 — the dashboard and screenshot are the deliverables.

---

### Step 6 — Baseline observations (optional, helps Phase 3/6)

After burst, note for yourself (scratch or later `REPORT.md` SLO section):

| Signal | Idle (approx.) | Under burst |
|--------|----------------|-------------|
| `gpu_cache_usage_perc` | ? | ? |
| TTFT p95 | ? | ? |
| `num_requests_waiting` peak | ? | ? |
| Preemptions/s | ? | ? |

These inform whether Phase 1 `--max-num-seqs` / `--gpu-memory-utilization` have headroom before the agent adds 2–3 calls per user request (Phase 3) and the 10 RPS SLO test (Phase 6).

```bash
curl -s http://localhost:8000/metrics | grep -E 'gpu_cache|num_requests|preemption'
```

---

## Phase 2 completion checklist

### H100 / submission (this session)

- [ ] Prometheus target `vllm` UP; all `serving.json` metric names exist in `/metrics`
- [ ] Grafana **vLLM serving** dashboard loads with latency / throughput / KV rows
- [ ] **Latency** — percentiles visible (TTFT and/or E2E + lifecycle localization)
- [ ] **Throughput** — running/waiting, token rates, success rate react under burst
- [ ] **KV cache** — `gpu_cache_usage_perc` and/or preemptions tell a headroom story
- [ ] Every panel reacts during `burst_vllm_load.sh` (parallel + kv-pressure or sustained)
- [ ] `screenshots/grafana_serving.png` captured on H100 with panels spiking
- [ ] `serving.json` committed if any H100 query fixes were needed

### Already done locally (reference only)

- [x] Dashboard designed and committed (`serving.json` — 3 categories, 13 panels)
- [x] PromQL patterns validated against 0.6B `/metrics`
- [x] `scripts/burst_vllm_load.sh` harness
- [x] Prometheus + Grafana provisioning wiring

---

## Troubleshooting (H100)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| All panels "No data" | Prometheus target DOWN | Confirm vLLM on `0.0.0.0:8000`; `docker compose up -d` |
| Some panels No data | Metric renamed in vLLM 0.10.x | Re-read `/metrics`; update query in `serving.json` |
| `histogram_quantile` empty | Too few samples / window too short | Run `burst_vllm_load.sh sustained`; widen to `[5m]` |
| Latency panels flat but throughput moves | Percentiles need sustained traffic | Use sustained mode, not single probe |
| KV cache stays near 0% | Burst too light for `--max-num-seqs 32` | Run `kv-pressure`; temporarily lower `max-num-seqs` |
| Grafana shows old 2-panel dashboard | Stale DB vs provisioned file | Restart Grafana; overwrite `serving.json` from repo |
| Percentiles look "too fast" | H100 is fast — that's real | Screenshot still valid if lines move during burst |
| Preemptions always 0 | Healthy headroom at test load | OK for Phase 2; push harder concurrency for Phase 6 story |

---

## What to defer (but plan for)

| Item | When |
|------|------|
| Prefix cache hit-rate panel | Phase 6 if tuning `--enable-prefix-caching` |
| Red/yellow KV thresholds tuned for production | Phase 6 after agent + 10 RPS load |
| `screenshots/grafana_before.png` / `after.png` | Phase 6 SLO iteration |
| `screenshots/grafana_eval_run.png` | Phase 5 eval batch |
| Correlating dashboard with agent traces | Phase 4 Langfuse + Phase 6 |
| Full 5-minute 10 RPS load test | Phase 6 (`load_test/driver.py`) |

**After Phase 3:** re-open this dashboard while driving `/answer` (not just raw probes) — prefill and queue panels will reflect schema-heavy agent prompts (~1.5–3K tokens).

---

## Suggested slot timeline (Phase 2)

Assumes Phase 1 vLLM already running (avoid 30B restart if possible):

| Block | Action |
|-------|--------|
| 0–5 min | Confirm scrape UP, restart Grafana, open **vLLM serving** |
| 5–10 min | Spot-check PromQL in Prometheus; one probe |
| 10–15 min | `burst_vllm_load.sh all` or sustained — verify every panel |
| 15–25 min | Fix any flat panels; re-burst if needed |
| 25–30 min | Capture `screenshots/grafana_serving.png`; commit JSON if changed |
| 30+ min | **Phase 3** — start agent on `:8001`, or keep vLLM warm for eval/SLO work |

Keep vLLM running across phases — restarting 30B costs 30+ minutes.

---

## PromQL reference (committed dashboard)

Copy starting points — already in `serving.json`:

```promql
# TTFT p95
histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))

# E2E p95
histogram_quantile(0.95, sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket[5m])))

# Prefill / decode p95
histogram_quantile(0.95, sum by (le) (rate(vllm:request_prefill_time_seconds_bucket[5m])))
histogram_quantile(0.95, sum by (le) (rate(vllm:request_decode_time_seconds_bucket[5m])))

# Throughput
rate(vllm:generation_tokens_total[1m])
sum(rate(vllm:request_success_total[1m]))

# KV cache
vllm:gpu_cache_usage_perc
rate(vllm:num_preemptions_total[1m])
```

---

## Relationship to later phases

| Phase | Dependency on Phase 2 |
|-------|------------------------|
| **1 (vLLM config)** | KV panels validate `--gpu-memory-utilization`, `max-num-seqs` headroom |
| **3 (Agent)** | Watch prefill + queue with real schema prompts (2–3 LLM calls/request) |
| **4 (Langfuse)** | Traces show *which* agent step was slow; dashboard shows *serving* saturation |
| **5 (Evals)** | Same dashboard during `run_eval.py` → `grafana_eval_run.png` |
| **6 (SLO / load test)** | Primary diagnosis surface during 5-minute 10 RPS test; before/after screenshots |

---

## Next phase

**Phase 3 (Agent)** — LangGraph text-to-SQL on top of the running vLLM stack:

```bash
# separate terminal, vLLM still on :8000
set -a && source .env && set +a
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

Re-open the Grafana dashboard while hitting `/answer` — throughput and prefill panels should look different from raw SQL probes.

See [README Phase 3](../README.md#phase-3-agent) and [`_local_dev/phase_3_plan.md`](_local_dev/phase_3_plan.md).
