# Phase 1 Plan — Nebius H100 VM (Final / Submission Environment)

This plan adapts [README.md Phase 1 (vLLM)](../README.md#phase-1-vllm) for the **Nebius H100 slot**. It builds on what we already validated locally in [`_local_dev/phase_1_plan.md`](_local_dev/phase_1_plan.md). Local Phase 1 is done; this session serves the real 30B model, tunes the production config, and produces submission artifacts.

Per [assignment_remarks.md](_local_dev/assignment_remarks.md): local work proved the API surface, probes, and Prometheus wiring — reserve the H100 for 30B serving, screenshots, and `REPORT.md` numbers.

---

## Goal

By the end of Phase 1 on Nebius you should have:

- vLLM serving **`Qwen/Qwen3-30B-A3B-Instruct-2507`** at `http://localhost:8000`
- `/v1/models`, `/v1/chat/completions`, `/health`, and `/metrics` all responding
- Prometheus target `vllm` **UP** at http://localhost:9090/targets
- 3–5 manual text-to-SQL probes from `evals/eval_set.jsonl` returning **sensible SQL on 30B** (not just valid syntax)
- Production flags in `scripts/start_vllm.sh` with one-line justifications in `REPORT.md`
- Screenshot at `screenshots/vllm_manual_query.png` ([CAPTURE.md](../screenshots/CAPTURE.md))

**Out of scope for Phase 1** (later phases): agent server on `:8001`, Grafana panel expansion (Phase 2), eval pass rates (Phase 5), SLO load test (Phase 6). You *will* revisit this config after Phase 3 when real agent prompts are wired.

---

## What you are optimizing for (context)

The assignment SLO is **end-to-end agent latency**, not raw vLLM latency alone:

> **P95 end-to-end agent latency under 5 seconds, 10+ RPS over a 5-minute window.**

Phase 1 is the **serving layer**. Your config should anticipate the agent workload:

| Dimension | Profile |
|-----------|---------|
| Model (fixed) | `Qwen/Qwen3-30B-A3B-Instruct-2507` — MoE, ~3B active params/token |
| Hardware (fixed) | 1× H100 80GB |
| Prompt size | ~1.5–3K tokens (question + DB schema) |
| Output | Short structured replies (SQL, JSON verify verdict) |
| Calls per user request | ~2–3 dependent LLM calls (generate → verify → optional revise) |

Phase 1 acceptance is: model loads, probes return good SQL, config is documented. Throughput/latency tuning for the SLO happens in Phase 6 — but choose flags *with that workload in mind*, not laptop defaults.

---

## What we already have locally (don't re-invent)

Validated on WSL2 / T500 (2026-06-13), per [`phase_1_plan.md`](_local_dev/phase_1_plan.md):

| Item | Local status | On Nebius |
|------|--------------|-----------|
| Launch script split | `start_vllm.sh` (H100) + `start_vllm_local.sh` (0.6B stand-in) | Use **`start_vllm.sh` only** |
| `.env` `VLLM_MODEL` | Local used `Qwen/Qwen3-0.6B` | Set to **`Qwen/Qwen3-30B-A3B-Instruct-2507`** (already in VM `.env`) |
| Health endpoints | `/v1/models`, `/health`, `/metrics` verified | Re-verify after 30B load |
| Prometheus scrape | Target `vllm` UP via `host.docker.internal:8000` | Same — needs `docker compose up -d` |
| Manual probes | `scripts/probe_vllm_sql.sh` — 5 eval questions | **Re-run same script** on 30B |
| SQL quality bar | Valid syntax on 0.6B | Must be **plausible + closer to gold** on 30B |
| `REPORT.md` stub | Production table with `*(fill on H100)*` placeholders | Fill flag table this session |
| Screenshot | Deferred | **`screenshots/vllm_manual_query.png`** this session |

**Do not copy local-only env vars to H100.** These were for T500 (sm 7.5) and must stay in `start_vllm_local.sh` only:

- `VLLM_USE_V1=0`
- `VLLM_ATTENTION_BACKEND=XFORMERS`
- `--enforce-eager`
- `--gpu-memory-utilization 0.70` / `--max-num-seqs 4`

On H100, use the v1 engine defaults (FlashAttention-2, `torch.compile` where applicable).

---

## Local vs Nebius (what changes)

| Local test (WSL / T500) | Nebius H100 VM |
|-------------------------|----------------|
| `Qwen/Qwen3-0.6B` stand-in | Fixed **`Qwen/Qwen3-30B-A3B-Instruct-2507`** |
| Smoke-test latency meaningless | First meaningful TTFT / throughput readings |
| SQL syntax check only | SQL should reference correct tables/columns for BIRD |
| Optional screenshot | **Required** `screenshots/vllm_manual_query.png` |
| Draft `REPORT.md` notes | **Final** Phase 1 config table in `REPORT.md` |
| ~1–3 GB weights, seconds to start | ~30–60+ GB weights; first run = download + compile (**30–90 min**) |

---

## Prerequisites (Nebius VM)

Confirm before starting vLLM (most come from [Phase 0](final_phase_0.md)):

- [ ] **Phase 0 complete** — `uv sync`, `data/bird/` (11 SQLite files), port forwards `8000` + `9090`
- [ ] **`nvidia-smi`** shows **H100 80GB**
- [ ] **`python3-dev`** installed (for `torch.compile`)
- [ ] **`.env`** — `HF_TOKEN` set, `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, Path A overrides **commented out**
- [ ] **`docker compose up -d`** — o11y stack running (Prometheus needs this for target check)
- [ ] **Port 8000 free** — `ss -tlnp | grep 8000` returns nothing
- [ ] **Disk headroom** — ~60 GB+ for weights + HF cache (`du -sh ~/.cache/huggingface 2>/dev/null`)

**VM sanity (current session):** H100 detected, 11 BIRD DBs present, vLLM 0.10.2 importable, ports 8000/8001 free.

---

## Execution steps

### Step 0 — Confirm environment for 30B

```bash
cd ~/mlops-assignment   # or your clone path
nvidia-smi
grep -E '^(HF_TOKEN|VLLM_MODEL)=' .env
ss -tlnp | grep 8000 || echo "port 8000 free"
```

Ensure `.env` has:

```bash
HF_TOKEN=<your-token>
VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507
# VLLM_BASE_URL=...   # leave commented — self-hosted on :8000
```

Start o11y stack if not already running:

```bash
docker compose up -d
# if permission denied: sudo usermod -aG docker $USER && re-login, or sudo docker compose up -d
```

---

### Step 1 — Initial production config in `scripts/start_vllm.sh`

The repo ships a **minimal** launcher (model + host + port). Expand it for the H100 workload. Start conservative, iterate one knob at a time.

**Suggested v1 starting point** (edit before first launch):

```bash
#!/usr/bin/env bash
set -euo pipefail

MODEL="Qwen/Qwen3-30B-A3B-Instruct-2507"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

ARGS=(
  --model "$MODEL"
  --host 0.0.0.0
  --port 8000
  --dtype bfloat16
  --max-model-len 8192          # covers 1.5–3K schema + headroom; trim if KV-bound
  --gpu-memory-utilization 0.92 # leave KV headroom; lower if OOM at startup
  --max-num-seqs 32             # concurrency seed; raise in Phase 6 toward 10+ RPS
  --enable-prefix-caching       # generate/verify/revise share schema prefix
  --enable-chunked-prefill      # long schema prefills
)

[[ -n "${HF_TOKEN:-}" ]] && ARGS+=(--hf-token "$HF_TOKEN")

cd "$REPO_ROOT"
exec uv run python -m vllm.entrypoints.openai.api_server "${ARGS[@]}"
```

**Why these levers** (assignment expects you to know this):

| Category | Why it matters here |
|----------|---------------------|
| **dtype / quantization** | MoE 30B weights must fit 80GB **with** KV cache for concurrent agent calls; try BF16 first, quant variants if OOM |
| **`max-model-len`** | Schema-heavy prompts ~1.5–3K; over-reserving wastes KV slots |
| **`gpu-memory-utilization`** | Trade weight footprint vs concurrent sequences |
| **`max-num-seqs`** | Primary concurrency knob for 10+ RPS × 2–3 calls/request |
| **`max-num-batched-tokens`** | Add if prefill/decode batching becomes the bottleneck (Phase 6) |
| **Prefix caching** | Same DB schema repeated across generate → verify → revise |
| **Chunked prefill** | Reduces TTFT spikes on long schemas |
| **MoE routing** | vLLM handles expert routing internally; watch logs for MoE-specific warnings |

Reference: [vLLM OpenAI server flags](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html)

**Tuning order** (from `REPORT.md` draft): `max-num-seqs` → KV headroom (`gpu-memory-utilization`) → `max-model-len` → prefix caching → revisit after Phase 3 agent prompts.

---

### Step 2 — Start vLLM (dedicated terminal)

First run downloads weights and may compile kernels — **plan 30–90 minutes**. Do not close the SSH session.

```bash
cd ~/mlops-assignment
bash scripts/start_vllm.sh
```

Wait for log line indicating OpenAI API server listening on `0.0.0.0:8000`.

**If OOM at startup:**

1. Lower `--gpu-memory-utilization` (e.g. 0.85)
2. Lower `--max-model-len` (e.g. 4096)
3. Lower `--max-num-seqs` (e.g. 16)
4. Consider FP8/AWQ/GPTQ variant if still OOM (update `--model` **and** `.env` `VLLM_MODEL` to match)

Change **one** knob per retry; note what you tried for `REPORT.md`.

---

### Step 3 — Health checks

From the VM or laptop (via `:8000` port forward):

```bash
curl -s http://localhost:8000/v1/models | jq .
curl -s http://localhost:8000/health
curl -s http://localhost:8000/metrics | head -30
```

Expect:

- Model id `Qwen/Qwen3-30B-A3B-Instruct-2507` in `/v1/models`
- vLLM Prometheus metrics (e.g. `vllm:num_requests_running`, `vllm:gpu_cache_usage_perc`)

**Prometheus target:**

Open http://localhost:9090/targets — job `vllm` should be **UP**.

If DOWN: confirm vLLM on `0.0.0.0:8000`, Docker stack running, and `infra/prometheus.yml` target `host.docker.internal:8000`.

---

### Step 4 — Manual text-to-SQL probes (30B)

Use the same 5 questions validated locally — now judge **quality**, not just syntax.

```bash
bash scripts/probe_vllm_sql.sh
```

**Starter questions** (same as local plan):

| # | `db_id` | Question (abbrev.) |
|---|---------|-------------------|
| 1 | `superhero` | Super Strength superpower count |
| 2 | `financial` | Male clients in 'Hl.m. Praha' district |
| 3 | `formula_1` | Circuit coordinates for Australian GP |
| 4 | `california_schools` | Top five schools by enrollment (NCES id) |
| 5 | `codebase_community` | Commentator badges in 2014 |

**Quality bar on 30B:**

- Valid SQLite (`SELECT` / `JOIN` / `WHERE` / aggregates)
- Plausible table/column names for that BIRD database
- Preferably executable against `data/bird/<db_id>.sqlite` with sensible row counts

Optional execution check:

```bash
# example — paste SQL from probe output
sqlite3 data/bird/superhero.sqlite "SELECT COUNT(*) FROM ..."
```

If SQL is weak but server is healthy, note for Phase 3 prompt tuning — Phase 1 only needs direct chat completions, not the full agent.

---

### Step 5 — Capture screenshot

Required artifact: **`screenshots/vllm_manual_query.png`**

Show in one frame (terminal multiplexer or stitched):

1. vLLM process/logs **or** `curl …/v1/models` proving 30B is served
2. One manual probe returning SQL (from `probe_vllm_sql.sh` or a single curl)

```bash
mkdir -p screenshots
# capture via Cursor screenshot, scrot, or phone photo of terminal + browser
```

See [screenshots/CAPTURE.md](../screenshots/CAPTURE.md).

---

### Step 6 — Document config in `REPORT.md`

Fill the **Production (H100)** table in [REPORT.md](../REPORT.md). Every flag you set (including defaults you * chose to keep*) gets a one-line justification tied to this workload.

Example row format:

| Flag | Value | One-line justification |
|------|-------|------------------------|
| `--enable-prefix-caching` | on | Agent makes 2–3 calls per request with identical schema prefix |

Add a short **H100 tuning notes** subsection: first-run observations (startup time, VRAM at idle, probe latency ballpark). Do **not** report SLO or eval pass rates yet — those come from Phases 5–6.

---

### Step 7 — Baseline metrics snapshot (optional, helps Phase 2/6)

While vLLM is idle and after a probe burst:

```bash
curl -s http://localhost:8000/metrics | grep -E 'gpu_cache|num_requests|generation_tokens'
```

Note idle KV usage % — useful when Phase 6 raises `--max-num-seqs`.

---

## Phase 1 completion checklist

### H100 / submission (this session)

- [x] `Qwen/Qwen3-30B-A3B-Instruct-2507` loads without OOM
- [x] `scripts/start_vllm.sh` updated with workload-aware flags (not bare defaults)
- [x] `curl http://localhost:8000/v1/models` shows 30B model id
- [x] `curl http://localhost:8000/metrics` returns vLLM metrics
- [x] Prometheus target `vllm` UP at http://localhost:9090/targets
- [x] `bash scripts/probe_vllm_sql.sh` — 5 questions, sensible SQL on 30B
- [x] `REPORT.md` — Phase 1 flag table filled with one-line justifications
- [ ] `screenshots/vllm_manual_query.png` captured on H100 (manual — run `bash scripts/phase1_screenshot_helper.sh`)

### Already done locally (reference only)

- [x] Stand-in model + probe script workflow
- [x] API + metrics + Prometheus wiring validated
- [x] Launch script split (prod vs local)
- [x] `REPORT.md` stub and tuning-order notes

---

## Troubleshooting (H100)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| CUDA OOM at startup | KV + weights exceed 80GB | Lower `gpu-memory-utilization`, `max-model-len`, `max-num-seqs`; try quant variant |
| CUDA OOM under load | Concurrency too high for KV | Reduce `max-num-seqs`; watch `vllm:gpu_cache_usage_perc` |
| Model download 401/403 | Gated model / bad token | Fix `HF_TOKEN` in `.env`; accept model license on HuggingFace |
| Very slow first request | Cold start / `torch.compile` | Normal; time subsequent probes |
| Port 8000 in use | Stale vLLM from prior session | `ss -tlnp \| grep 8000` — kill old process |
| Prometheus `vllm` DOWN | Docker not running / wrong target | `docker compose up -d`; confirm vLLM on `0.0.0.0:8000` |
| `docker: permission denied` | User not in `docker` group | `sudo usermod -aG docker $USER` + re-login |
| Nonsense SQL despite healthy server | Direct probe lacks full schema | Expected for minimal Phase 1 prompt; full schema comes in Phase 3 agent |
| `transformers` import errors | Version mismatch | Repo pins `transformers>=4.55.2,<5.0` — re-run `uv sync` |

---

## What to defer (but plan for)

| Item | When |
|------|------|
| Final `--max-num-seqs` for 10+ RPS | Phase 6 load test |
| `--max-num-batched-tokens` tuning | Phase 6 if queue/TTFT bound |
| Agent `MAX_ITERATIONS` interaction | Phase 3 agent + Phase 6 |
| Eval pass rates | Phase 5 on this same vLLM endpoint |
| `screenshots/grafana_serving.png` | Phase 2 burst / Phase 6 load |
| Quantization decision | Only if BF16 OOMs or concurrency headroom insufficient |

**After Phase 3:** re-open `start_vllm.sh` with real prompt token counts from Langfuse traces (schema blocks may differ from minimal probes).

---

## Suggested slot timeline (Phase 1)

| Block | Action |
|-------|--------|
| 0–5 min | Confirm `.env`, `docker compose up -d`, port forwards, edit `start_vllm.sh` |
| 5–60 min | First `bash scripts/start_vllm.sh` — model download + compile (variable) |
| 60–75 min | Health checks, Prometheus UP, `probe_vllm_sql.sh` |
| 75–90 min | Screenshot, fill `REPORT.md` Phase 1 table |
| 90+ min | **Phase 2** — Grafana panels under 30B burst, or keep vLLM running for Phase 3 agent |

Keep vLLM running across phases if slot time allows — restarting 30B is expensive.

---

## Next phase

**Phase 2 (o11y core)** — with 30B metrics flowing:

1. Extend `infra/grafana/provisioning/dashboards/serving.json` (latency, throughput, KV cache)
2. Fire a request burst; confirm panels react
3. Optional: capture practice panels (final `grafana_serving.png` comes from Phase 6 load)

See [phase_2_plan.md](_local_dev/phase_2_plan.md) (adapt H100 sections; ignore local stand-in notes).

**Phase 3 (agent)** — point agent at the running vLLM:

```bash
# separate terminal, after Phase 1 stable
set -a && source .env && set +a
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

Then revisit Phase 1 config with real 2–3 call/agent-request patterns before Phase 6 SLO work.
