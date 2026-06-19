# Phase 0 Plan — Local Test Environment

This plan adapts [README.md Phase 0](../README.md#phase-0-setup) for **local development on your machine** (WSL2 / laptop), not the cloud H100 VM. Per [assignment_remarks.md](assignment_remarks.md): build and validate the full pipeline locally first; reserve the H100 for final runs and submission artifacts.

---

## Goal

By the end of Phase 0 locally you should have:

- Python deps installed (`uv sync`)
- `.env` created from the template
- BIRD dev subset under `data/bird/` (~500 MB)
- Observability stack running (Prometheus, Grafana, Langfuse)
- All three UIs reachable in your browser on `localhost`
- A clear path to Phase 1+ without blocking on H100 or SSH port forwards

---

## Local vs VM (what changes)

| README (VM) | Local test phase |
|---|---|
| SSH port forwards for 3000, 9090, 3001, 8000, 8001 | Services bind to `localhost` directly — no port forwarding |
| Remote-SSH / `ssh -L …` setup | Work in repo on WSL; open URLs in Windows browser via WSL localhost forwarding |
| H100 assumed for vLLM | **Skip 30B for now** — use a small local model or an external OpenAI-compatible API (see `.env.example`) |
| Submission screenshots from H100 | Local Phase 0 only validates infra; final screenshots come later on H100 |

Ports still matter locally (same numbers):

| Port | Service | Phase 0 check |
|------|---------|---------------|
| 3000 | Grafana | http://localhost:3000 |
| 9090 | Prometheus | http://localhost:9090 |
| 3001 | Langfuse | http://localhost:3001 |
| 8000 | vLLM (host, not Docker) | Phase 1 — optional locally with small model |
| 8001 | Agent server | Phase 3+ |

---

## Prerequisites (local)

1. **Python 3.11+** with dev headers (`python3-dev` on Debian/Ubuntu) — needed later for vLLM `torch.compile`.
2. **[uv](https://docs.astral.sh/uv/)** — dependency manager used by the assignment.
3. **Docker + docker-compose** — runs Prometheus, Grafana, Langfuse and backing services.
   - On WSL2: enable **Docker Desktop → Settings → Resources → WSL Integration** for your distro.
   - Verify: `docker compose version` and `docker ps` work inside WSL.
4. **Disk space** — ~2 GB free (BIRD ~500 MB + Docker images + optional small model weights).
5. **Network** — `load_data.py` downloads BIRD from Aliyun OSS.

Optional for later local agent work (not required to finish Phase 0):

- NVIDIA GPU + CUDA for local vLLM with a small model
- Or `OPENAI_API_KEY` + uncommented overrides in `.env` to point the agent at a hosted API

---

## Current repo state (baseline)

As of 2026-06-12 (Phase 0 implemented locally):

| Item | Status |
|------|--------|
| Repo cloned | Yes |
| `uv sync` / `.venv` | Yes |
| `.env` | Yes |
| `data/bird/` | Yes — 11 SQLite DBs, 30 eval + 1500 perf questions |
| `docker compose up` | Yes — Prometheus, Grafana, Langfuse running |

---

## Execution steps

### Step 1 — Install Python dependencies

```bash
cd /home/danar/repos/ai_performance/mlops/hw2_llm_inference_o11y
uv sync
```

**Verify:** `uv run python -c "import vllm, langgraph, langfuse; print('ok')"`

---

### Step 2 — Create environment file

```bash
cp .env.example .env
```

For **local test phase only**, you can leave most values empty:

- `HF_TOKEN` — only needed when downloading gated models or running vLLM locally.
- `LANGFUSE_*` — filled in Phase 4 after Langfuse UI signup.
- **Optional shortcut for agent dev (Phase 3):** uncomment and set `VLLM_BASE_URL`, `VLLM_MODEL`, `OPENAI_API_KEY` in `.env` to avoid running vLLM on laptop.

Do **not** commit `.env`.

---

### Step 3 — Load BIRD dataset

```bash
uv run python scripts/load_data.py
```

Downloads `dev.zip`, extracts SQLite DBs, and generates:

- `data/bird/<db_id>.sqlite`
- `evals/eval_set.jsonl` (30 questions)
- `load_test/perf_pool.jsonl` (1500 questions)

**Verify:**

```bash
ls data/bird/*.sqlite | head
wc -l evals/eval_set.jsonl load_test/perf_pool.jsonl
```

Expect ~30 eval lines and ~1500 perf lines.

---

### Step 4 — Start observability stack

```bash
docker compose up -d
```

First pull may take several minutes (Langfuse stack: Postgres, ClickHouse, Redis, MinIO).

**Verify containers:**

```bash
docker compose ps
```

All services should be `running` (Langfuse web may take 1–2 min after dependencies are healthy).

**Verify UIs in browser:**

| URL | Expected |
|-----|----------|
| http://localhost:9090 | Prometheus UI — Status → Targets (vLLM target will be down until Phase 1) |
| http://localhost:3000 | Grafana login — `admin` / `admin` |
| http://localhost:3001 | Langfuse — local signup (any email works) |

---

### Step 5 — Sanity checks beyond “page loads”

**Prometheus**

- Open http://localhost:9090/targets
- `vllm` job may show **DOWN** — expected before vLLM starts on `:8000`.

**Grafana**

- Log in, confirm Prometheus datasource is provisioned (Configuration → Data sources).
- Starter dashboard from `infra/grafana/provisioning/` should appear after Phase 1 metrics exist.

**Langfuse**

- Create account → create org/project (defaults may already exist: Course / Default).
- No API keys needed until Phase 4; note where to find them later.

---

## What to defer until H100 / VM

Keep these out of local Phase 0 scope:

- Serving `Qwen/Qwen3-30B-A3B-Instruct-2507` (needs ~H100-class VRAM)
- Tuning vLLM flags for 10+ RPS / P95 &lt; 5s SLO
- Submission screenshots (`screenshots/`) — must come from H100 run per assignment remarks
- SSH port-forward workflow — only needed when working on the cloud VM from a laptop

---

## Local vLLM option (optional, Phase 1 preview)

If you have a GPU locally and want to smoke-test before H100:

1. Pick a small instruct model, e.g. `Qwen/Qwen2.5-1.5B-Instruct` or similar.
2. Edit `scripts/start_vllm.sh` (or run vLLM manually) with that model.
3. Set `VLLM_MODEL` in `.env` to match.
4. Start: `bash scripts/start_vllm.sh` (long first run — model download).
5. Quick test:

```bash
curl http://localhost:8000/v1/models
curl http://localhost:8000/metrics | head
```

Otherwise, use the `.env` OpenAI-compatible override and skip local vLLM entirely until the H100 slot.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `docker: command not found` | Docker not in WSL | Install Docker Desktop; enable WSL integration; restart WSL |
| Port already in use | Another process on 3000/9090/3001 | `ss -tlnp \| grep -E '3000\|9090\|3001'` — stop conflicting service or change compose ports |
| Langfuse not loading | Stack still starting | `docker compose logs -f langfuse-web` — wait for Postgres/ClickHouse healthy |
| Grafana empty dashboard | No vLLM metrics yet | Normal until Phase 1 |
| `load_data.py` download fails | Network / firewall | Retry; or set `BIRD_DEV_URL` if mirror provided |
| Browser can’t reach localhost from Windows | WSL networking | Use `localhost` (WSL2 forwards by default); try http://127.0.0.1:3000 |

---

## Phase 0 completion checklist

- [x] `uv sync` succeeds
- [x] `.env` exists (from `.env.example`)
- [x] `data/bird/` populated with SQLite files
- [x] `evals/eval_set.jsonl` and `load_test/perf_pool.jsonl` generated
- [x] `docker compose up -d` — all containers healthy
- [x] Prometheus UI loads at http://localhost:9090
- [x] Grafana UI loads at http://localhost:3000 (`admin` / `admin`)
- [x] Langfuse UI loads at http://localhost:3001 (account created — **manual**: sign up in browser)
- [ ] Documented decision: local small-model vLLM **or** external API for agent dev until H100 → **defer vLLM to H100; use OpenAI-compatible API override in `.env` for local agent dev if needed**

---

## Next phase

**Phase 1 (vLLM)** — start inference, confirm `/v1/chat/completions` and `/metrics`, tune config on H100. Locally you may only do a lightweight smoke test; final config and screenshot belong on the VM.
