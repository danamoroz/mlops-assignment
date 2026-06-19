# Phase 2 Plan — Local Test Environment

This plan adapts [README.md Phase 2 (o11y core)](../README.md#phase-2-o11y-core) for **local development on your machine** (WSL2 / laptop), not the cloud H100 VM. Per [assignment_remarks.md](assignment_remarks.md): build and validate the Grafana dashboard locally against CPU/small-model vLLM; reserve the H100 for the final screenshot and submission-quality load tests.

---

## Goal

By the end of Phase 2 **locally** you should have:

- A Grafana dashboard covering **latency**, **throughput**, and **KV cache** health
- Every panel visibly reacting when you fire a burst of requests
- Dashboard JSON committed under `infra/grafana/provisioning/dashboards/`
- A **draft** screenshot workflow (optional locally); final artifact on H100

**Final submission artifacts** (H100 only):

- `screenshots/grafana_serving.png` — full dashboard with panels reacting during a real burst on `Qwen3-30B-A3B`
- Same dashboard JSON (already committed locally; re-verify queries still work at 30B scale)

---

## What you are building (context)

Phase 2 is about **serving-layer observability**. A teammate should be able to open the dashboard during a load test and answer:

1. **Is the system slow?** If yes, **where** in the request lifecycle (queue → prefill → decode → e2e)?
2. **Is throughput keeping up?** Tokens out, requests served, queue depth, generation rate.
3. **Do we have KV cache headroom?** Or are we about to preempt / evict / swap?

The assignment deliberately does **not** name every metric. Exploring `http://localhost:8000/metrics` and mapping metrics to these questions is part of the work. Use the [vLLM metrics docs](https://docs.vllm.ai/en/latest/usage/metrics.html) and the upstream [metrics design doc](https://github.com/vllm-project/vllm/blob/main/docs/design/metrics.md) as references.

### Starter dashboard (already in repo)

`infra/grafana/provisioning/dashboards/serving.json` ships with **2 panels**:

| Panel | Metric / query | Category |
|-------|----------------|----------|
| Requests running | `vllm:num_requests_running` | Throughput / concurrency |
| Generated tokens / sec | `rate(vllm:generation_tokens_total[1m])` | Throughput |

Build on these — do not delete them unless you fold them into a better layout.

### Stack wiring (already configured)

| Component | Config | Notes |
|-----------|--------|-------|
| Prometheus scrape | `infra/prometheus.yml` → `host.docker.internal:8000/metrics` every **5s** | vLLM runs on host, not in compose |
| Grafana datasource | `infra/grafana/provisioning/datasources/prometheus.yml` | UID `prometheus` |
| Dashboard provisioning | `infra/grafana/provisioning/dashboards/dashboards.yml` | Auto-loads JSON from provisioning folder |
| Grafana UI | http://localhost:3000 (admin / admin) | Dashboard refresh already `5s` in starter JSON |

---

## Local vs H100 (what changes)

| README (VM / H100) | Local test phase |
|---|---|
| Dashboard validated under real 30B load | Validate **panel wiring** with CPU/small vLLM; absolute numbers are meaningless |
| Screenshot during burst at serving scale | Optional local draft; **required** screenshot from H100 |
| KV cache pressure at 10+ RPS | Can still **trigger** KV/queue panels with concurrent requests on tiny model |
| Hosted OpenAI API | **No `/metrics`** — cannot do Phase 2 without local vLLM |

**Recommendation:** Use `scripts/start_vllm_local.sh` (`Qwen/Qwen3-0.6B`) so Prometheus scrapes real vLLM metrics. Re-run the same burst test on H100 before submitting.

---

## Prerequisites (local)

Assumes [Phase 0](phase_0_plan.md) and [Phase 1](phase_1_plan.md) local checklist items are done:

- [x] `docker compose up -d` — Prometheus + Grafana healthy
- [x] vLLM stand-in running on `:8000` with `/metrics` exposed
- [x] Prometheus target `vllm` **UP** at http://localhost:9090/targets
- [x] `.env` `VLLM_MODEL` matches the served model id (for load-test scripts)

Create screenshot directory if missing:

```bash
mkdir -p screenshots
```

---

## Execution steps

### Step 1 — Confirm the metrics pipeline

With vLLM and compose running:

```bash
# Raw metrics from vLLM
curl -s http://localhost:8000/metrics | grep '^vllm:' | head -40

# Prometheus sees the target
open http://localhost:9090/targets    # job vllm = UP

# Grafana loads the starter dashboard
open http://localhost:3000
# → Dashboards → "vLLM serving"
```

Fire one request and confirm counters move:

```bash
bash scripts/probe_vllm_sql.sh
```

In Prometheus → Graph, try `vllm:generation_tokens_total` — value should increase after the probe.

---

### Step 2 — Explore `/metrics` and categorize

Dump and skim all `vllm:` series. Group what you find into the three assignment categories. Expect **gauges**, **counters**, and **histograms** (with `_bucket`, `_sum`, `_count` suffixes).

**Latency (histograms — use percentiles in Grafana)**

Look for metrics that decompose the request lifecycle. Common families (names may vary slightly by vLLM version):

| Lifecycle stage | Typical metric | What it tells you |
|-----------------|----------------|-------------------|
| Time to first token | `vllm:time_to_first_token_seconds` | User-perceived "how long until output starts" — often prefill-bound |
| Queue wait | `vllm:request_queue_time_seconds` | Scheduler backlog before work starts |
| Prefill | `vllm:request_prefill_time_seconds` | Prompt processing cost (schema-heavy agent workload) |
| Decode | `vllm:request_decode_time_seconds` | Token generation cost |
| End-to-end | `vllm:e2e_request_latency_seconds` | Total wall time per request |
| Inter-token | `vllm:inter_token_latency_seconds` | Streaming smoothness / decode stalls |

**Throughput (counters + gauges — rates and concurrency)**

| Signal | Typical metric | Panel idea |
|--------|----------------|------------|
| Active work | `vllm:num_requests_running` | Already in starter |
| Waiting / swapped | `vllm:num_requests_waiting`, `vllm:num_requests_swapped` | Queue pressure |
| Tokens generated | `vllm:generation_tokens_total` | Already in starter as `rate(...)` |
| Prompt tokens processed | `vllm:prompt_tokens_total` | Input throughput |
| Request outcomes | `vllm:request_success_total`, failure counters | Error budget |
| Token length distribution | `vllm:request_generation_tokens`, `vllm:request_prompt_tokens` | p50/p95 output size |

**KV cache (gauges — headroom and eviction risk)**

| Signal | Typical metric | Panel idea |
|--------|----------------|------------|
| Cache fill level | `vllm:kv_cache_usage_perc` | **Primary** headroom gauge (0–1 or 0–100%) |
| CPU offload cache | `vllm:cpu_cache_usage_perc` | If CPU KV offload enabled |
| Prefix cache efficiency | `vllm:prefix_cache_hits` / `vllm:prefix_cache_queries` | Hit rate for repeated prompts (agent schema) |
| Preemption signal | Rising `num_requests_swapped` + high KV usage | "About to evict" story |

Pick metrics that **actually exist** in your running vLLM build — do not paste queries for metrics your `/metrics` dump does not expose.

**PromQL percentile pattern** (for any histogram `vllm:foo_seconds`):

```promql
histogram_quantile(
  0.95,
  sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket[5m]))
)
```

Repeat for `0.50`, `0.90`, `0.99` as separate series or use Grafana's **Heatmap** / **Percentile** transforms. Use a `[$__rate_interval]` or `[5m]` window aligned with dashboard refresh.

---

### Step 3 — Design the dashboard layout

Aim for one screen a tired on-call engineer can read at a glance. Suggested row structure (adjust `gridPos` in JSON or drag in UI):

```
┌─────────────────────────────────────────────────────────────────┐
│  ROW: Latency (p50 / p95 / p99)                                 │
│  [ TTFT percentiles ] [ E2E percentiles ] [ Prefill vs Decode ] │
│  [ Queue time p95 ]   [ Inter-token p95 ]                       │
├─────────────────────────────────────────────────────────────────┤
│  ROW: Throughput                                                │
│  [ Requests running ] [ Waiting ]     [ Gen tokens/s ] (exist)  │
│  [ Request rate ]     [ Prompt tok/s] [ Success vs fail rate ]  │
├─────────────────────────────────────────────────────────────────┤
│  ROW: KV cache & scheduler pressure                             │
│  [ kv_cache_usage_perc ] [ prefix cache hit % ]                 │
│  [ swapped / waiting if non-zero under load ]                   │
└─────────────────────────────────────────────────────────────────┘
```

**Panel types:**

- **Time series** — percentiles, rates, gauges over time
- **Stat** (optional) — current KV cache %, running requests (big number for 3 AM readability)
- **Bar gauge** (optional) — KV cache usage as a fuel gauge

Set dashboard **refresh** to `5s` (already in starter) and time range to **Last 15 minutes** while testing.

---

### Step 4 — Build latency panels

**In Grafana UI** (easiest for iteration):

1. Open **vLLM serving** → Add panel → Prometheus datasource.
2. For each histogram, add queries for p50/p95/p99 using `histogram_quantile`.
3. Set unit to **seconds (s)**; enable legend; use distinct colors per percentile.
4. Add panel descriptions: *"If TTFT p95 spikes but decode is flat → prefill bottleneck."*

**Minimum latency coverage for assignment:**

- [ ] At least one **e2e** or **TTFT** percentile panel
- [ ] At least one panel that localizes slowness (**prefill vs decode**, or **queue vs e2e**)
- [ ] Percentiles visible (not just averages — histograms exist for a reason)

**Sanity check:** Single-request probe should produce a visible blip; sustained load should show stable percentile lines.

---

### Step 5 — Build throughput panels

Keep and extend the starter panels:

- **Requests running** — already present; consider adding **waiting** on the same chart.
- **Gen tokens/s** — already present; consider `rate(vllm:prompt_tokens_total[1m])` alongside for input/output balance.

Add panels that answer "are we serving fast enough?":

- Request completion rate: `sum(rate(vllm:request_success_total[1m]))`
- Queue depth trending up under load → concurrency limit or KV pressure

**Sanity check:** During a burst, running/waiting should rise, token rates should spike, then settle.

---

### Step 6 — Build KV cache panels

The assignment asks for metrics that answer: **headroom for more concurrency, or about to evict?**

Minimum:

- [ ] **`vllm:kv_cache_usage_perc`** as time series and/or stat panel (thresholds: green &lt; 70%, yellow 70–85%, red &gt; 85% — tune subjectively)
- [ ] Optional: prefix cache hit rate if you enable prefix caching later in Phase 1 config

**How to make it move locally** (tiny model still works):

- Lower `--max-num-seqs` in `start_vllm_local.sh` (e.g. 2–4)
- Fire **parallel** requests with longer `max_tokens` to hold KV blocks longer

```bash
# Simple parallel burst (adjust model from .env)
MODEL=$(grep ^VLLM_MODEL= .env | cut -d= -f2-)
for i in $(seq 1 8); do
  curl -sf http://localhost:8000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a long SQL explanation $i\"}],\"max_tokens\":512}" &
done
wait
```

Watch `kv_cache_usage_perc` and `num_requests_waiting` climb during the burst.

---

### Step 7 — Load test to verify every panel reacts

README requires **every panel visibly reacts** during a burst. Use a repeatable local harness:

**Option A — parallel probes (quick):**

```bash
# 20 requests, 4 at a time
seq 1 20 | xargs -P4 -I{} bash -c 'bash scripts/probe_vllm_sql.sh >/dev/null'
```

**Option B — sustained loop (better for percentiles):**

```bash
# ~2 minutes of traffic
end=$((SECONDS + 120))
while [ $SECONDS -lt $end ]; do
  bash scripts/probe_vllm_sql.sh >/dev/null &
  sleep 0.5
done
wait
```

**Verification checklist while Grafana is open (refresh 5s):**

| Category | Expect to see during burst |
|----------|----------------------------|
| Latency | Percentile lines move up (may be noisy on CPU — that's OK locally) |
| Throughput | `running`/`waiting` &gt; 0, token rates spike |
| KV cache | `kv_cache_usage_perc` increases; may plateau below 1.0 on tiny model |

If a panel stays flat, trace the PromQL in Prometheus Graph first — fix the query before blaming the model.

---

### Step 8 — Export and commit dashboard JSON

After editing in Grafana UI:

1. **Dashboard settings** → **JSON Model** → copy, **or**
2. **Save dashboard** — with file provisioning, changes may also be saved to Grafana's DB; for submission you need the file updated.

Ensure the committed file is:

```
infra/grafana/provisioning/dashboards/serving.json
```

**Commit workflow:**

```bash
# Restart Grafana to confirm provisioning loads your JSON cleanly
docker compose restart grafana

# Open dashboard — all panels should appear without manual import
open http://localhost:3000
```

Prefer editing JSON directly only if you are comfortable with `gridPos` and panel schema; UI is faster for PromQL iteration.

**Do not** commit Grafana admin password changes or local datasource overrides — only the dashboard JSON under `infra/grafana/provisioning/dashboards/`.

---

### Step 9 — Screenshot (draft locally, final on H100)

Required artifact: `screenshots/grafana_serving.png`

Capture when:

- Dashboard time range covers the burst window (e.g. **Last 15 minutes**)
- **All rows** visible in one screenshot (zoom browser to fit, or use Grafana **Play** → snapshot if needed)
- Multiple panels show clear activity spikes

**Local:** optional practice screenshot for your notes.

**H100:** re-run the same burst harness against `Qwen3-30B-A3B` with your Phase 1 config; capture the submission screenshot there.

---

## Phase 2 completion checklist

### Local test phase (now)

- [ ] `/metrics` explored; metric choices documented for yourself (scratch notes OK)
- [ ] Dashboard has **latency** section with **percentiles**
- [ ] Dashboard has **throughput** section (extends starter panels)
- [ ] Dashboard has **KV cache** section with headroom signal
- [ ] Every panel reacts during a local burst test
- [ ] `infra/grafana/provisioning/dashboards/serving.json` updated and loads after `docker compose restart grafana`
- [ ] PromQL queries validated in Prometheus before Grafana

### H100 / submission (later)

- [ ] Re-verify all panels against 30B metrics (some histogram buckets differ in scale)
- [ ] Burst test at meaningful concurrency (post–Phase 1 tuning)
- [ ] `screenshots/grafana_serving.png` captured on H100
- [ ] Dashboard still readable under real load (no "flat line" panels)

---

## What to defer until H100

- Submission screenshot with representative serving load
- KV cache behavior at real `max-model-len` and agent prompt sizes (~1.5–3K tokens)
- Correlating dashboard signals with the Phase 6 SLO (P95 agent latency, 10+ RPS)
- Tuning red/yellow thresholds on KV cache for production-like headroom

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| All panels "No data" | Prometheus target DOWN | Start vLLM on `:8000`; check http://localhost:9090/targets |
| Some panels No data | Metric not exposed in your vLLM version | Re-read `/metrics`; pick alternate metric from same category |
| `histogram_quantile` empty | Too few samples / rate window too short | Run sustained burst; widen range to `[5m]`; check `_bucket` series exist |
| Panels flat during burst | Query wrong metric name or missing `rate()` on counter | Test query in Prometheus UI first |
| Grafana shows old dashboard | UI saved to DB, file not updated | Export JSON to `serving.json`; restart Grafana |
| KV cache stays at 0% locally | Tiny prompts, low concurrency | Parallel requests + higher `max_tokens`; lower `max-num-seqs` |
| Percentiles extremely noisy on CPU | Expected with 0.6B CPU backend | OK for wiring validation; smooth out on H100 |
| `host.docker.internal` fails on Linux | Docker host gateway | `docker-compose.yml` already has `extra_hosts`; verify WSL networking |

---

## PromQL cheat sheet (copy starting points, then adapt)

```promql
# E2E latency p95
histogram_quantile(0.95, sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket[5m])))

# TTFT p95
histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))

# Prefill p95
histogram_quantile(0.95, sum by (le) (rate(vllm:request_prefill_time_seconds_bucket[5m])))

# Decode p95
histogram_quantile(0.95, sum by (le) (rate(vllm:request_decode_time_seconds_bucket[5m])))

# Generation throughput (starter)
rate(vllm:generation_tokens_total[1m])

# KV cache usage (0-1)
vllm:kv_cache_usage_perc

# Prefix cache hit rate (if counters exist)
rate(vllm:prefix_cache_hits_total[5m]) / rate(vllm:prefix_cache_queries_total[5m])
```

Metric names may include `model_name` labels — use `sum by (le)` or filter `{model_name="..."}` if you add template variables later.

---

## Relationship to later phases

| Phase | Dependency on Phase 2 |
|-------|------------------------|
| **1 (vLLM config)** | KV cache panels inform `gpu-memory-utilization`, `max-model-len`, `max-num-seqs` tuning on H100 |
| **3 (Agent)** | Agent adds 2–3 calls/request — watch prefill + queue panels with real schema prompts |
| **4 (Langfuse)** | Complements Grafana: traces explain *which* agent step was slow; dashboard shows *serving* saturation |
| **6 (SLO / load test)** | Same dashboard is your primary view during the 5-minute load test |

After Phase 3, re-open the dashboard while driving the agent (not just raw probes) — prompt token counts and prefix cache hit rate may look very different.

---

## Next phase

**Phase 3 (Agent)** — build the LangGraph text-to-SQL flow on top of the serving stack. See [README Phase 3](../README.md#phase-3-agent).
