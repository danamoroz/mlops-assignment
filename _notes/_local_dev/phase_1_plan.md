# Phase 1 Plan — Local Test Environment

This plan adapts [README.md Phase 1 (vLLM)](../README.md#phase-1-vllm) for **local development on your machine** (WSL2 / laptop), not the cloud H100 VM. Per [assignment_remarks.md](assignment_remarks.md): validate the inference stack locally first; reserve the H100 for final tuning, screenshots, and submission artifacts.

---

## Goal

By the end of Phase 1 **locally** you should have:

- vLLM running as an OpenAI-compatible server on `http://localhost:8000`
- `/v1/models` and `/v1/chat/completions` responding
- `/metrics` exposed so Prometheus can scrape (Phase 2 prep)
- 3–5 manual text-to-SQL probes from `evals/eval_set.jsonl` returning plausible SQL
- A **draft** launch config and notes (to finalize in `REPORT.md` on H100)

**Final submission artifacts** (H100 only):

- vLLM serving `Qwen/Qwen3-30B-A3B-Instruct-2507` with a tuned config
- Screenshot at `screenshots/vllm_manual_query.png`
- Config flags + one-line justifications in `REPORT.md`

---

## What you are optimizing for (context)

The assignment SLO is **end-to-end agent latency**, not raw vLLM latency alone:

> **P95 end-to-end agent latency under 5 seconds, 10+ RPS over a 5-minute window.**

Phase 1 is the **serving layer**. Your config should anticipate the agent workload:

| Dimension | Profile |
|-----------|---------|
| Model (fixed on H100) | `Qwen/Qwen3-30B-A3B-Instruct-2507` |
| Hardware (fixed on H100) | 1× H100 80GB |
| Prompt size | ~1.5–3K tokens (question + DB schema) |
| Output | Short structured replies (SQL, JSON verify verdict) |
| Calls per user request | ~2–3 dependent LLM calls (generate → verify → optional revise) |

Locally you **cannot** hit the real SLO numbers. The point of local Phase 1 is to prove the server works, wire observability, and learn which config levers you will tune on H100.

---

## Local vs H100 (what changes)

| README (VM / H100) | Local test phase |
|---|---|
| Serve `Qwen/Qwen3-30B-A3B-Instruct-2507` | Use a **stand-in model** (CPU or small GPU) |
| Tune for 10+ RPS / P95 &lt; 5s agent SLO | Smoke-test only; absolute latency/throughput unrepresentative |
| Screenshot + `REPORT.md` config | Draft notes locally; **final** screenshot and flags on H100 |
| `scripts/start_vllm.sh` as production config | Keep prod script for H100; optional separate local script |

### Recommended local backend (pick one)

| Option | Good for | `/metrics`? | Notes |
|--------|----------|-------------|-------|
| **CPU vLLM + small Qwen** (e.g. `Qwen/Qwen3-0.6B`) | Phase 1 smoke + Phase 2 Grafana | Yes | Slow; matches prod API surface. [CPU install docs](https://docs.vllm.ai/en/latest/getting_started/installation/cpu.html). |
| **GPU vLLM + small instruct model** (e.g. `Qwen2.5-1.5B-Instruct`) | Faster local iteration if you have CUDA | Yes | Still not 30B; good for API/debug flow. |
| **Hosted OpenAI-compatible API** via `.env` | Agent dev (Phase 3+) without local vLLM | **No** | Skip Phase 1 locally; Prometheus `vllm` target stays DOWN. |

**Recommendation for this repo:** CPU or small-GPU vLLM locally so Prometheus and Grafana can be validated in Phase 2. Use `.env` overrides only when you explicitly want to skip running vLLM.

---

## Prerequisites (local)

Assumes [Phase 0](phase_0_plan.md) is done:

- [x] `uv sync` — vLLM in `.venv`
- [x] `.env` from `.env.example`
- [x] `data/bird/` + `evals/eval_set.jsonl`
- [x] `docker compose up -d` — Prometheus scraping `host.docker.internal:8000`

Additional for Phase 1:

1. **`HF_TOKEN` in `.env`** — set if the stand-in model requires HuggingFace auth.
2. **Disk / RAM** — small model ~1–3 GB weights; CPU vLLM is RAM-heavy.
3. **Optional GPU** — NVIDIA driver + CUDA inside WSL if using GPU vLLM.
4. **`python3-dev`** — already noted in README; needed for vLLM `torch.compile` on H100.

Create screenshot directory (empty until H100):

```bash
mkdir -p screenshots
```

---

## Execution steps

### Step 1 — Choose stand-in model and split configs

Keep `scripts/start_vllm.sh` as the **H100 / 30B** launcher (modify on VM).

For local smoke tests, either:

- Add `scripts/start_vllm_local.sh` with a small model, **or**
- Temporarily edit `MODEL=` in `start_vllm.sh` locally (revert before H100).

Example local launcher sketch:

```bash
#!/usr/bin/env bash
set -euo pipefail

MODEL="Qwen/Qwen3-0.6B"   # CPU-friendly stand-in; swap if you have GPU

exec uv run python -m vllm.entrypoints.openai.api_server \
    --model "$MODEL" \
    --host 0.0.0.0 \
    --port 8000
    # add CPU-specific flags per vLLM docs when on CPU
```

Align `.env`:

```bash
VLLM_MODEL=Qwen/Qwen3-0.6B   # must match served model id locally
# VLLM_BASE_URL=http://localhost:8000/v1   # default in agent code
```

---

### Step 2 — Start vLLM

In a dedicated terminal (first run downloads weights — can take a while):

```bash
cd /home/danar/repos/ai_performance/mlops/hw2_llm_inference_o11y
bash scripts/start_vllm.sh   # or start_vllm_local.sh
```

Wait until logs show the OpenAI API server listening on port 8000.

**Verify health:**

```bash
curl -s http://localhost:8000/v1/models | jq .
curl -s http://localhost:8000/health
curl -s http://localhost:8000/metrics | head -20
```

Expect model id in `/v1/models` and vLLM Prometheus metrics (e.g. `vllm:num_requests_running`).

---

### Step 3 — Confirm Prometheus scrape

Open http://localhost:9090/targets — job `vllm` should be **UP**.

If DOWN on WSL/Docker:

- Confirm vLLM is listening on `0.0.0.0:8000`
- Check `infra/prometheus.yml` target `host.docker.internal:8000`
- On Linux without `host.docker.internal`, you may need `extra_hosts` in `docker-compose.yml` or point Prometheus at the host gateway IP

This unblocks Phase 2 dashboard work even with a tiny model.

---

### Step 4 — Manual text-to-SQL probes (3–5 from eval set)

Phase 1 is **direct** chat completions, not the Phase 3 agent. Pick 3–5 lines from `evals/eval_set.jsonl` with varying `db_id` complexity.

**Suggested starter questions** (easy → harder):

| # | `db_id` | Question (abbrev.) |
|---|---------|-------------------|
| 1 | `superhero` | "How many superheroes have the super power of Super Strength?" |
| 2 | `financial` | "How many male clients in 'Hl.m. Praha' district?" |
| 3 | `formula_1` | "What is the coordinates location of the circuits for Australian grand prix?" |
| 4 | `california_schools` | Top five schools by enrollment (NCES id) |
| 5 | `codebase_community` | Commentator badges in 2014 |

For each row, send a minimal text-to-SQL prompt (schema optional for Phase 1; full schema comes in Phase 3):

```bash
QUESTION='How many superheroes have the super power of "Super Strength"?'

curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "$(grep ^VLLM_MODEL= .env | cut -d= -f2-)" \
    --arg q "$QUESTION" \
    '{
      model: $model,
      messages: [
        {role: "system", content: "You are a SQLite expert. Reply with only a single SQL query, no explanation."},
        {role: "user", content: ("Question: " + $q + "\nDatabase: superhero")}
      ],
      temperature: 0
    }')" | jq -r '.choices[0].message.content'
```

**What “sensible SQL” means locally:**

- Valid-looking SQLite (`SELECT` / `JOIN` / `WHERE` / aggregates)
- References plausible table/column names for that BIRD database
- Not required to match `gold_sql` exactly on the stand-in model
- On H100 with 30B, quality bar rises — re-run the same probes there

Optionally execute returned SQL against `data/bird/<db_id>.sqlite` with `sqlite3` to catch obvious garbage.

---

### Step 5 — Explore config levers (local: learn; H100: tune)

README intentionally does not list flags. Use this checklist when building your H100 config. Start conservative on VM, load-test in Phase 6, iterate.

| Category | Why it matters for this workload |
|----------|----------------------------------|
| **Quantization / dtype** | 30B MoE must fit H100 80GB with headroom for KV cache; FP8/AWQ/GPTQ variants reduce memory |
| **`max-model-len`** | Must cover 1.5–3K input + short output; excess length wastes KV memory |
| **`gpu-memory-utilization`** | Trade model weights vs KV cache capacity for concurrent requests |
| **`max-num-seqs` / batching** | Higher concurrency for 10+ RPS; watch latency inflation |
| **`max-num-batched-tokens`** | Throughput vs latency for mixed prefill/decode |
| **Prefix / prompt caching** | Repeated schema across agent calls may help multi-step requests |
| **Chunked prefill** | Long prompts (schema-heavy) — reduces prefill latency spikes |
| **MoE-specific** | Expert parallelism, routing — relevant for Qwen3-30B-A3B |

**Local workflow:**

1. Run with defaults → note OOM / startup errors
2. Change **one** knob at a time on H100
3. Record flag, value, and observed effect in a scratch doc
4. Revisit after Phase 3 agent is wired (real prompt sizes differ)

Reference: [vLLM OpenAI server flags](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html)

---

### Step 6 — Draft `REPORT.md` (finalize on H100)

`REPORT.md` does not exist yet. Create a stub locally; complete after H100 tuning.

```markdown
## Phase 1 — vLLM configuration

**Model:** Qwen/Qwen3-30B-A3B-Instruct-2507
**Hardware:** 1× H100 80GB

| Flag | Value | One-line justification |
|------|-------|------------------------|
| `--model` | ... | ... |
| ... | ... | ... |

**Local smoke-test notes:** (stand-in model, date, what was verified)
**H100 tuning notes:** (iterations, load-test observations — fill in Phase 6)
```

Do **not** report eval pass rates or SLO numbers from the local stand-in model.

---

### Step 7 — Screenshot (defer to H100)

Required artifact: `screenshots/vllm_manual_query.png` showing:

1. vLLM process/logs or `/v1/models` proving 30B is served
2. One manual query returning SQL output

Capture on the H100 VM after Phase 1 config is stable. Local stand-in screenshots are optional for your own notes only.

---

## Phase 1 completion checklist

### Local test phase (now)

- [x] Stand-in model chosen; `.env` `VLLM_MODEL` matches
- [x] vLLM starts and listens on `:8000`
- [x] `curl http://localhost:8000/v1/models` succeeds
- [x] `curl http://localhost:8000/metrics` returns vLLM metrics
- [x] Prometheus target `vllm` is UP at http://localhost:9090/targets
- [x] 3–5 manual eval questions return plausible SQL
- [x] Draft config notes started (scratch or `REPORT.md` stub)
- [x] Decision recorded: local script vs prod script separation

### H100 / submission (later)

- [ ] `Qwen/Qwen3-30B-A3B-Instruct-2507` loads without OOM
- [ ] Same manual probes re-run; SQL quality acceptable on 30B
- [ ] Config tuned with workload-aware flags (post–Phase 3 revisit)
- [ ] `REPORT.md` — final flags + one-line justifications
- [ ] `screenshots/vllm_manual_query.png` from H100 run

---

## What to defer until H100

- Serving the fixed 30B MoE model
- Meaningful latency / throughput / KV-cache sizing for 10+ RPS
- Submission screenshot and final `REPORT.md` config table
- Any reported SLO or eval pass-rate numbers

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| CUDA OOM on laptop | Stand-in model too large for GPU | Switch to smaller model or CPU vLLM |
| vLLM CPU install fails | Missing CPU build / deps | Follow [CPU install docs](https://docs.vllm.ai/en/latest/getting_started/installation/cpu.html); check `python3-dev` |
| Model download 401 | Gated model | Set `HF_TOKEN` in `.env`; `huggingface-cli login` |
| Prometheus `vllm` DOWN | Host networking | Ensure vLLM on `:8000`; fix Docker → host routing |
| Empty / nonsense SQL locally | Tiny stand-in model limits | Expected locally; validate API plumbing only |
| Port 8000 in use | Old vLLM process | `ss -tlnp \| grep 8000` — kill stale process |
| Slow first request | Cold start / compile | Normal; watch subsequent requests |

---

## Relationship to later phases

| Phase | Dependency on Phase 1 |
|-------|------------------------|
| **2 (Grafana)** | Needs `/metrics` — CPU/small vLLM locally is enough |
| **3 (Agent)** | Agent calls `VLLM_BASE_URL` / `VLLM_MODEL`; can use hosted API without local vLLM |
| **5–6 (Evals / SLO)** | Must point at 30B on H100 for reported numbers |

After Phase 3, **revisit Phase 1 config** with real prompt token counts and 2–3 calls per request before Phase 6 load testing.

---

## Next phase

**Phase 2 (o11y core)** — with vLLM metrics flowing, extend the Grafana starter dashboard (`infra/grafana/provisioning/dashboards/serving.json`) for latency, throughput, and KV cache. See [README Phase 2](../README.md#phase-2-o11y-core).
