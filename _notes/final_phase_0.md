# Phase 0 Plan — Nebius H100 VM (Final / Submission Environment)

This plan adapts [README.md Phase 0](../README.md#phase-0-setup) for the **Nebius H100 slot**. It builds on what we already validated locally in [`_local_dev/phase_0_plan.md`](_local_dev/phase_0_plan.md). Local Phase 0 is done; this session reproduces the observability stack on the VM and prepares for Phase 1 (30B vLLM).

Per [assignment_remarks.md](_local_dev/assignment_remarks.md): develop locally first (done), then run the full pipeline on H100 for submission artifacts.

---

## Goal

By the end of Phase 0 on Nebius you should have:

- Cursor or SSH connected to the H100 VM with **five ports forwarded**
- Repo cloned, `uv sync` complete, `python3-dev` present
- `.env` created and tuned for **H100 / self-hosted vLLM** (not Path A API overrides)
- BIRD dev subset under `data/bird/` (~500 MB)
- Observability stack running (`docker compose up -d`)
- Three UIs reachable from your **laptop browser** via port forwards
- Prometheus `vllm` target **DOWN** (expected until Phase 1 starts vLLM on `:8000`)

---

## What we already have locally (don't re-invent)

Validated on WSL2 (2026-06-12):

| Item | Local status | On Nebius |
|------|--------------|-----------|
| Repo + code | `origin` → `https://github.com/danamoroz/mlops-assignment` | Fresh `git clone` (or pull if repo already on VM) |
| `uv sync` / `.venv` | Done | Re-run on VM (Linux + CUDA env differs) |
| `.env` | Done (Path A / local keys) | **New** `.env` on VM — H100 values, no Nebius API override |
| `data/bird/` | 11 SQLite DBs, eval + perf JSONL | Re-run `load_data.py` on VM (~500 MB download) |
| Docker o11y stack | Prometheus, Grafana, Langfuse healthy | Re-run `docker compose up -d` on VM |
| Langfuse account | Created locally | **New** signup on VM Langfuse (separate instance) |
| Agent / eval code | Built through Phase 7 locally | Already in repo — no Phase 0 action |

**Time budget:** ~30–45 min on a fresh VM (mostly Docker image pull + BIRD download). Slot time is precious — do Phase 0 immediately after SSH works, before Phase 1 model download.

---

## Local vs Nebius (what changes)

| Local test (WSL) | Nebius H100 VM |
|------------------|----------------|
| No port forwarding — `localhost` in WSL browser | **Must** forward 3000, 9090, 3001, 8000, 8001 to laptop |
| Path A optional (`VLLM_BASE_URL` in `.env`) | Use self-hosted vLLM: `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507` |
| Skip 30B locally | 30B is the submission model — Phase 1+ on this slot |
| Docker Desktop WSL integration | Native Docker on VM (verify `docker compose`) |
| `HF_TOKEN` optional until vLLM | **Set `HF_TOKEN` in `.env` before Phase 1** (gated model download) |
| Practice screenshots | Submission screenshots start from this environment |

### Ports (forward all five now)

| Port | Service | Phase 0 check |
|------|---------|---------------|
| 3000 | Grafana | http://localhost:3000 |
| 9090 | Prometheus | http://localhost:9090 |
| 3001 | Langfuse | http://localhost:3001 |
| 8000 | vLLM (host, not Docker) | Phase 1 — forward now anyway |
| 8001 | Agent server | Phase 3+ — forward now anyway |

---

## Prerequisites (Nebius VM)

Confirm on the VM before starting:

1. **1× H100 80GB** — assignment hardware assumption
2. **Docker + docker-compose** — `docker compose version`, `docker ps`
3. **Python 3.11+** with **`python3-dev`** — required for vLLM `torch.compile` in Phase 1
4. **[uv](https://docs.astral.sh/uv/)** — install if not on the image: `curl -LsSf https://astral.sh/uv/install.sh | sh`
5. **git**
6. **Disk** — ~2 GB free for BIRD + Docker volumes; **much more** for 30B weights in Phase 1 (~60 GB+ depending on quant)
7. **Network** — outbound HTTPS for `load_data.py` (Aliyun OSS), HuggingFace, Docker Hub
8. **`HF_TOKEN`** — HuggingFace token with access to `Qwen/Qwen3-30B-A3B-Instruct-2507` (paste into `.env` before Phase 1)

Optional but recommended:

- **NVIDIA driver + CUDA** visible: `nvidia-smi` (needed Phase 1, good sanity check in Phase 0)

---

## Step 0 — Connect and forward ports

### Option A — Cursor / VS Code Remote-SSH (recommended)

1. Install Remote-SSH extension
2. `F1` → *Remote-SSH: Connect to Host* → add Nebius VM (`<user>@<vm-host>`)
3. Open repo folder on the VM
4. **Ports** panel → *Forward a Port* for each: `3000`, `9090`, `3001`, `8000`, `8001`

### Option B — Plain SSH (fallback)

```bash
ssh -L 3000:localhost:3000 \
    -L 9090:localhost:9090 \
    -L 3001:localhost:3001 \
    -L 8000:localhost:8000 \
    -L 8001:localhost:8001 \
    <user>@<vm-host>
```

Keep this session open (or use Cursor port forwards). If a UI does not load on the laptop, check forwards first.

---

## Execution steps

### Step 1 — Clone repo and install dependencies

```bash
git clone https://github.com/danamoroz/mlops-assignment.git
cd mlops-assignment   # or hw2_llm_inference_o11y if renamed on push
uv sync
```

**Verify:**

```bash
uv run python -c "import vllm, langgraph, langfuse; print('ok')"
python3 --version    # expect 3.11+
dpkg -l python3-dev 2>/dev/null || rpm -q python3-devel 2>/dev/null || echo "install python3-dev"
nvidia-smi
```

If `import vllm` fails, fix env before Phase 1; Phase 0 o11y stack does not need vLLM running.

---

### Step 2 — Create environment file

```bash
cp .env.example .env
```

Edit `.env` for **H100 submission path**:

```bash
# Required before Phase 1
HF_TOKEN=<your-hf-token>

# Self-hosted vLLM on VM (default in .env.example — keep these)
VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507

# Langfuse — docker-compose seeds these on first boot; or create keys in UI later (Phase 4)
LANGFUSE_PUBLIC_KEY=pk-lf-course-local-dev
LANGFUSE_SECRET_KEY=sk-lf-course-local-dev
LANGFUSE_HOST=http://localhost:3001
```

**Do not** enable Path A overrides on the H100 slot:

```bash
# Leave commented — for local dev only
# VLLM_BASE_URL=https://api.tokenfactory.nebius.com/v1
# NEBIUS_API_KEY=...
```

Do **not** commit `.env`.

---

### Step 3 — Load BIRD dataset

```bash
uv run python scripts/load_data.py
```

Downloads `dev.zip`, extracts SQLite DBs, generates:

- `data/bird/<db_id>.sqlite` (11 files)
- `evals/eval_set.jsonl` (30 questions)
- `load_test/perf_pool.jsonl` (1500 questions)

**Verify:**

```bash
ls data/bird/*.sqlite | wc -l    # expect 11
wc -l evals/eval_set.jsonl load_test/perf_pool.jsonl
```

Expect ~30 eval lines and ~1500 perf lines.

---

### Step 4 — Start observability stack

```bash
docker compose up -d
```

First pull may take several minutes (Langfuse: Postgres, ClickHouse, Redis, MinIO).

**Verify containers:**

```bash
docker compose ps
```

All services should be `running`. Langfuse web may need 1–2 min after dependencies are healthy.

**Verify UIs from laptop browser** (via port forwards):

| URL | Expected |
|-----|----------|
| http://localhost:9090 | Prometheus UI |
| http://localhost:3000 | Grafana — `admin` / `admin` |
| http://localhost:3001 | Langfuse — local signup |

---

### Step 5 — Sanity checks beyond “page loads”

**Prometheus**

- Open http://localhost:9090/targets
- `vllm` job shows **DOWN** — expected until Phase 1 starts vLLM on `:8000`

**Grafana**

- Log in (`admin` / `admin`)
- Configuration → Data sources → Prometheus provisioned
- Starter dashboard from `infra/grafana/provisioning/` may be empty until vLLM metrics exist (Phase 1–2)

**Langfuse**

- Sign up (any email works on local instance)
- Create org/project if prompted (defaults may exist: Course / Default)
- API keys: use seeded keys from `.env` or Settings → API Keys (Phase 4)
- This is a **new** Langfuse instance — traces from local WSL will not appear here

---

## Phase 0 completion checklist

- [ ] SSH / Cursor connected to Nebius VM
- [ ] Ports **3000, 9090, 3001, 8000, 8001** forwarded to laptop
- [ ] `uv sync` succeeds on VM
- [ ] `python3-dev` installed
- [ ] `nvidia-smi` shows H100
- [ ] `.env` exists — `HF_TOKEN` set, Path A overrides **disabled**
- [ ] `data/bird/` populated (11 SQLite files)
- [ ] `evals/eval_set.jsonl` and `load_test/perf_pool.jsonl` generated
- [ ] `docker compose up -d` — all containers healthy
- [ ] Prometheus UI loads at http://localhost:9090
- [ ] Grafana UI loads at http://localhost:3000
- [ ] Langfuse UI loads at http://localhost:3001 (account created)
- [ ] Prometheus target `vllm` DOWN (OK for Phase 0)

---

## Troubleshooting (VM)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| UI won't load on laptop | Port forward missing / SSH session dropped | Re-forward all five ports; reconnect Cursor Remote-SSH |
| `docker: permission denied` | User not in `docker` group | `sudo usermod -aG docker $USER` + re-login, or use `sudo docker compose` |
| Langfuse not loading | Stack still starting | `docker compose logs -f langfuse-web` — wait for Postgres/ClickHouse healthy |
| Port already in use on VM | Stale process from prior session | `ss -tlnp \| grep -E '3000\|9090\|3001'` — stop conflicting service |
| `load_data.py` download fails | Network / firewall | Retry; check outbound HTTPS to Aliyun OSS |
| Grafana empty dashboard | No vLLM metrics yet | Normal until Phase 1 |
| `uv sync` slow or fails | Cold cache / missing system libs | Install build deps; ensure Python 3.11+ |
| Wrong repo state | Old clone on VM | `git pull` or fresh clone from `danamoroz/mlops-assignment` |

---

## What Phase 0 deliberately does *not* include

Keep these for later phases on the same slot:

- Starting vLLM / downloading 30B weights — **Phase 1** (`bash scripts/start_vllm.sh`)
- Grafana dashboard tuning under load — **Phase 2**
- Agent server on `:8001` — **Phase 3**
- Langfuse trace wiring — **Phase 4**
- Eval runs and SLO numbers — **Phases 5–6**
- Submission screenshots — **Phases 1–7** ([screenshots/CAPTURE.md](../screenshots/CAPTURE.md))

---

## Suggested slot timeline (Phase 0 + immediate next)

| Block | Action |
|-------|--------|
| 0–10 min | SSH, port forwards, `nvidia-smi`, install uv if needed |
| 10–25 min | `git clone`, `uv sync`, `cp .env.example .env`, set `HF_TOKEN` |
| 25–40 min | `load_data.py`, `docker compose up -d`, UI sanity checks |
| 40+ min | **Phase 1** — `bash scripts/start_vllm.sh` (long first run: model download + compile) |

Do not burn H100 slot time debugging port forwards — fix connectivity before heavy downloads.

---

## Next phase

**Phase 1 (vLLM)** — on this VM:

```bash
bash scripts/start_vllm.sh
```

Then from laptop (via `:8000` forward):

```bash
curl http://localhost:8000/v1/models
curl http://localhost:8000/metrics | head
```

Confirm Prometheus target `vllm` → **UP**. See [phase_1_plan.md](_local_dev/phase_1_plan.md) for H100 tuning notes (local sections about small models / Path A do not apply here).
