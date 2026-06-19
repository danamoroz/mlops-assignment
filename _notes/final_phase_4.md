# Phase 4 Plan — Nebius H100 VM (Final / Submission Environment)

This plan adapts [README.md Phase 4 (Agent o11y)](../README.md#phase-4-agent-o11y) for the **Nebius H100 slot**. It builds on what we already validated locally in [`_local_dev/phase_4_plan.md`](_local_dev/phase_4_plan.md). Local Phase 4 wiring is done in `agent/server.py` and `agent/trace_tags.py`; this session **re-runs the smoke batch on 30B**, confirms trace quality on the VM Langfuse instance, and captures the two submission screenshots.

Per [assignment_remarks.md](_local_dev/assignment_remarks.md): wire and debug Langfuse tracing locally first; **submission screenshots** (`screenshots/langfuse_trace.png`, `screenshots/langfuse_tags.png`) must come from **H100 + Qwen3-30B** runs ([screenshots/CAPTURE.md](../screenshots/CAPTURE.md)).

---

## Goal

By the end of Phase 4 on Nebius you should have:

- Langfuse on the **VM** receiving traces from every `POST /answer` when `LANGFUSE_*` keys are in `.env`
- **10 agent runs** on **`Qwen/Qwen3-30B-A3B-Instruct-2507`**, tagged with metadata you will filter on in Phase 6
- At least **one trace** with a **`revise`** span in the waterfall (`generate_sql` → `execute` → `verify` → `revise` → …)
- LLM spans showing **prompt, response, latency, and token counts** on 30B (meaningful numbers for later phases)
- **`screenshots/langfuse_trace.png`** — single trace waterfall with `revise` visible
- **`screenshots/langfuse_tags.png`** — trace list with `run_type`, `batch_id`, `config_label` (and post-run tags) visible

**Out of scope for Phase 4** (later phases): full 30-question eval pass rates (Phase 5), 10 RPS × 5 min load test (Phase 6), `REPORT.md` agent-value paragraph (Phase 7). Phase 4 only needs working traces + submission screenshots on 30B.

---

## What you are building (context)

Phase 4 is **observability wiring**, not new agent logic. Langfuse sits on the LangGraph invocation and records each node and LLM call as nested spans.

```
POST /answer  (question, db, tags?)
       │
       ▼
graph.invoke(state, config={ callbacks: [Langfuse], metadata: tags })
       │
       ├── attach_schema
       ├── generate_sql   ── LLM span
       ├── execute
       ├── verify         ── LLM span
       └── revise (0–2×)  ── LLM span  →  execute → verify
```

README shows:

```python
from langfuse.callback import CallbackHandler
handler = CallbackHandler()
result = graph.invoke(state, config={"callbacks": [handler]})
```

This repo uses **Langfuse v4** with LangChain integration — keep the existing import:

```python
from langfuse.langchain import CallbackHandler
```

Graph node names in `agent/graph.py` (`generate_sql`, `execute`, `verify`, `revise`) are what Langfuse should show as span names in the waterfall.

---

## What we already have locally (don't re-invent)

Validated on WSL2 / laptop (2026-06), per [`phase_4_plan.md`](_local_dev/phase_4_plan.md):

| Item | Local status | On Nebius |
|------|--------------|-----------|
| Langfuse `CallbackHandler` | `agent/server.py` — per-request handler when keys set | **No code changes** — confirm keys + restart agent |
| Metadata → Langfuse tags | `agent/trace_tags.py` — `langfuse_tags`, `langfuse_trace_name` | Same; `config_label` auto = `h100-30b` when `VLLM_MODEL` contains `30b` |
| Post-run outcome tags | `annotate_trace_outcome` → `iterations:N`, `agent_ok:true/false` | Verify on 30B traces |
| Request `tags` field | `AnswerRequest.tags` on `POST /answer` | Pass on every smoke request |
| Smoke batch script | `scripts/phase4_smoke.py` — 10 eval questions + tags | Re-run with H100 `batch_id` |
| Langfuse stack | `docker-compose.yml` — web `:3001` | **Separate VM instance** — WSL traces do not appear here |
| Env template | `.env.example` — `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST` | Use seeded keys or create project keys in VM UI |
| Dependency | `pyproject.toml` — `langfuse>=4.0,<5.0` | Already in `uv sync` from Phase 0 |

**Do not re-implement the handler inside `graph.py`.** `server.py` already attaches callbacks at invoke time via `build_invoke_config()`.

**Do not copy local-only trace batches into submission narrative.** Local runs may use `config_label=local-0.6b` or Path A — Phase 4 submission artifacts must be from **30B on H100**.

---

## Local vs Nebius (what changes)

| Local test (WSL / 0.6B or Path A) | Nebius H100 VM |
|-------------------------------------|----------------|
| Tracing wiring validated | Same wiring; **30B** latency and token counts |
| Langfuse at WSL `localhost:3001` | Langfuse at **VM** `localhost:3001` (port-forward `:3001`) |
| Practice screenshots optional | **Required** `langfuse_trace.png`, `langfuse_tags.png` |
| `config_label=local-0.6b` or hosted API label | `config_label=h100-30b` (auto from `VLLM_MODEL`) |
| Revise loop on stand-in model | Revise loop on **30B** — use Phase 3 question that hit `iterations >= 2` |
| Directional token/latency numbers | Numbers you may cite in Phase 6 / `REPORT.md` |

Phase 4 is mostly **configuration + smoke + screenshots** on H100. No graph or prompt changes expected unless traces are missing spans (see Troubleshooting).

---

## Prerequisites (Nebius VM)

Confirm before starting Phase 4 (most come from [Phase 0](final_phase_0.md)–[Phase 3](final_phase_3.md)):

- [ ] **Phase 0 complete** — `docker compose up -d`, port forward **3001** (Langfuse) + **8001** (agent)
- [ ] **Phase 1 complete** — 30B vLLM healthy on `:8000`
- [ ] **Phase 3 complete** — agent on `:8001`, at least one 30B run with `iterations >= 2` (see [`phase3_h100_scratch_log.md`](phase3_h100_scratch_log.md))
- [ ] **`.env`** — `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, no Path A `VLLM_BASE_URL` override
- [ ] **Langfuse stack up** — `docker compose ps` shows `langfuse-web`, `langfuse-worker` running
- [ ] **`LANGFUSE_*` in `.env`** — seeded dev keys from Phase 0 or keys from VM Langfuse UI

Quick preflight:

```bash
cd ~/mlops-assignment
docker compose ps | grep -E 'langfuse|grafana|prometheus'
curl -sf http://localhost:8000/health && echo "vLLM ok"
curl -sf http://localhost:8001/health | jq .
grep -E '^LANGFUSE_' .env
```

Expect agent health:

```json
{"status": "ok", "langfuse_enabled": true}
```

If `langfuse_enabled` is `false`, set keys and **restart uvicorn** (handler is decided at import time).

**Not required for Phase 4 acceptance:** Grafana panel tuning, eval harness, load driver.

---

## Execution steps

### Step 0 — Confirm Langfuse on the VM

Open http://localhost:3001 (via SSH port forward). First boot after `docker compose up -d` can take 1–2 minutes.

Docker-compose may pre-seed a dev account:

- Email: `dev@langfuse.com`
- Password: see `LANGFUSE_INIT_USER_PASSWORD` in `docker-compose.yml` (default course dev password)

If you created a separate project in Phase 0, use **Project Settings → API Keys** and ensure `.env` matches.

Required `.env` entries:

```bash
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
LANGFUSE_HOST=http://localhost:3001
```

**Important:** This is a **new Langfuse instance** on the VM. Traces from local WSL development will **not** appear here.

---

### Step 1 — Start (or restart) the agent with Langfuse enabled

Terminal layout (same as Phase 3):

```bash
# Terminal 1 — if not already running
docker compose up -d
bash scripts/start_vllm.sh

# Terminal 2 — agent (restart after .env key changes)
set -a && source .env && set +a
export VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

Sanity check:

```bash
curl -s http://localhost:8001/health | jq .
```

---

### Step 2 — One tagged manual request (confirm trace before batch)

Use a question that triggered revise on 30B in Phase 3 (Australian GP coordinates on `formula_1`):

```bash
curl -s -X POST http://localhost:8001/answer \
  -H "Content-Type: application/json" \
  -d '{
    "question": "What is the coordinates location of the circuits for Australian grand prix?",
    "db": "formula_1",
    "tags": {
      "run_type": "smoke",
      "source": "phase4_manual",
      "db_id": "formula_1",
      "batch_id": "h100-phase4-manual"
    }
  }' | jq '{ok, iterations, error, history: [.history[] | {node, iteration}]}'
```

In Langfuse → **Tracing** → latest trace (within ~30s):

| Check | Expected |
|-------|----------|
| Trace exists | One new trace per `/answer` |
| Span tree | `attach_schema`, `generate_sql`, `execute`, `verify`, optionally `revise` |
| LLM spans | Under `generate_sql`, `verify`, `revise` — input, output, latency, tokens |
| Metadata / tags | `run_type`, `source`, `db_id`, `batch_id`, **`config_label:h100-30b`** |
| Post-run tags | `iterations:2` (or higher), `agent_ok:true` or `false` |

If the manual trace looks good, proceed to the 10-question batch.

---

### Step 3 — Fire 10 questions through the agent (30B)

README requires **10 questions**. Use the smoke script (first 10 lines of `evals/eval_set.jsonl`, diverse `db_id`):

```bash
BATCH_ID="h100-phase4-$(date +%Y%m%d-%H%M)"
uv run python scripts/phase4_smoke.py \
  --count 10 \
  --batch-id "$BATCH_ID" \
  --source phase4_h100
```

The script prints a JSON summary including `with_revise` count. **You need at least one** `iterations >= 2` for the submission screenshot.

If `with_revise: 0`, re-run the Phase 3 formula_1 question manually or pick another eval line known to revise on 30B — do not change verifier prompts just for a screenshot.

Wait 10–30s for Langfuse worker ingestion, then refresh the trace list.

**Filter in Langfuse:** Metadata or tag `batch_id` = your `BATCH_ID`.

---

### Step 4 — Inspect waterfall on 30B

1. Open **Tracing** in Langfuse.
2. Pick a trace where the agent response had **`iterations >= 2`** (prefer `formula_1` from the batch).
3. Expand the span tree:

```
Trace (answer:formula_1 or LangGraph run)
├── attach_schema
├── generate_sql
│   └── ChatOpenAI / LLM generation
├── execute
├── verify
│   └── ChatOpenAI / LLM generation
├── revise
│   └── ChatOpenAI / LLM generation
├── execute
└── verify
```

4. Click each LLM span — confirm **input**, **output**, **latency**, **tokens** (prompt / completion / total).

Note ballpark 30B token counts and latencies per span — useful when tuning vLLM in Phase 6 and writing `REPORT.md` (Phase 7). You do not need to paste numbers into `REPORT.md` yet.

---

### Step 5 — Capture submission screenshots

Per [screenshots/CAPTURE.md](../screenshots/CAPTURE.md):

| File | What to capture |
|------|-----------------|
| `screenshots/langfuse_trace.png` | **Single trace** waterfall — **`revise` visible** in the tree; LLM span detail readable |
| `screenshots/langfuse_tags.png` | **Trace list** for your H100 batch — columns/filters showing **`run_type`**, **`batch_id`**, **`config_label`** (and ideally `iterations`, `agent_ok`) |

Tips:

- Use the trace from Step 4 with the revise loop expanded.
- For the tags screenshot, show the filtered list for `batch_id=h100-phase4-...` (or your batch id), not unrelated local smoke runs.
- Capture from the **laptop browser** via port forward `:3001`.

Optional helper (also used in Phase 6/7 for load-test trace samples):

```bash
bash scripts/run_phase7_h100.sh trace-sample h100-phase4-trace h100-30b-baseline
# then capture screenshots manually
```

---

### Step 6 — Lock tag schema for Phase 5 and Phase 6

Phase 6 diagnosis (*"why was this request slow?"*) depends on **consistent, filterable tags**. Use the same keys on smoke, eval, and load runs:

| Key | Example (H100 Phase 4) | Use in Phase 6 |
|-----|------------------------|----------------|
| `run_type` | `smoke`, later `eval`, `load_test` | Separate dev noise from SLO runs |
| `batch_id` | `h100-phase4-20250619-1430` | Group one session |
| `db_id` | `formula_1`, `superhero`, … | Compare latency by database |
| `source` | `phase4_h100`, `phase4_manual`, `run_eval`, `load_driver` | Which client fired the request |
| `config_label` | `h100-30b` (auto) or `h100-30b-baseline` (load driver override) | Compare tuning iterations |

**Rules:**

- Pass the same keys on **every** `/answer` in a given experiment.
- Do **not** mix 0.6B and 30B traces under the same `config_label`.
- `load_test/driver.py` sends tags in Phase 6 — Phase 4 proves the path works.

Phase 5 eval runs should use `run_type=eval` and `batch_id=eval_baseline` (or similar) when you add tags to `evals/run_eval.py`.

---

## Phase 4 completion checklist

### H100 / submission (this session)

- [ ] Langfuse UI loads at http://localhost:3001 on the VM
- [ ] `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST` in VM `.env`
- [ ] Agent restarted; `GET /health` → `"langfuse_enabled": true`
- [ ] One manual tagged `POST /answer` produces a trace within ~30s
- [ ] Trace waterfall on **30B** shows `generate_sql`, `execute`, `verify` spans
- [ ] At least one **30B** trace shows **`revise`** in the span tree
- [ ] LLM spans show prompt, response, latency, token counts on 30B
- [ ] 10 questions fired via `phase4_smoke.py` with `batch_id=h100-phase4-...`
- [ ] Trace list filterable by `run_type=smoke` and/or `batch_id`
- [ ] `screenshots/langfuse_trace.png` — revise loop visible
- [ ] `screenshots/langfuse_tags.png` — metadata tags visible in trace list

### Already done locally (reference only)

- [x] `agent/server.py` — per-request Langfuse handler + `build_invoke_config`
- [x] `agent/trace_tags.py` — tag merge, `langfuse_tags`, post-run `iterations` / `agent_ok`
- [x] `scripts/phase4_smoke.py` — 10-question batch with tags
- [x] Langfuse docker-compose stack
- [x] Local trace wiring validated (any backend)

---

## Troubleshooting (H100)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| No traces at all | Keys missing or agent not restarted | Set `.env` keys; restart uvicorn |
| `langfuse_enabled: false` | Empty or wrong `LANGFUSE_*` | Fix `.env`; restart agent |
| `POST /answer` 500 after adding keys | Wrong host/keys; Langfuse down | Check `LANGFUSE_HOST=http://localhost:3001`; `docker compose ps` |
| Traces appear but no node names | Callbacks not passed | Confirm `server.py` uses `build_invoke_config` — should already |
| Flat trace, no LLM children | Wrong handler import | Keep `langfuse.langchain.CallbackHandler` (v4) |
| Metadata tags missing | Empty `tags` in request | Include `tags` in JSON; check trace **Metadata** / **Tags** panel |
| `config_label` wrong | `VLLM_MODEL` not 30B | Set `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507` before starting agent |
| Traces delayed | Worker backlog | Wait 10–30s; `docker compose logs langfuse-worker` |
| Langfuse UI blank / 502 | Stack still starting | `docker compose logs -f langfuse-web` |
| No revise in batch | 30B passed verify on first try | Re-run known Phase 3 revise question; check `with_revise` in smoke JSON |
| WSL traces on wrong instance | Looking at laptop Langfuse | Use **VM** port forward `:3001` — separate Postgres/ClickHouse |
| Slow `/answer` during smoke | Normal on 30B cold-ish start | Sequential smoke is fine; load test is Phase 6 |

During **Phase 6 load tests**, if Langfuse drops spans under concurrency, set `LANGFUSE_DISABLED=1` for the load run and use `trace-sample` afterward (see [`_local_dev/phase_6_plan.md`](_local_dev/phase_6_plan.md)). Phase 4 smoke is sequential — Langfuse should keep up.

---

## File touch map

| File | Action |
|------|--------|
| `.env` | Confirm `LANGFUSE_*` on VM (seeded or UI keys) |
| `agent/server.py` | **No changes expected** |
| `agent/trace_tags.py` | **No changes expected** |
| `agent/graph.py` | **No changes expected** — node names drive span labels |
| `scripts/phase4_smoke.py` | **Run on H100** — `--batch-id h100-phase4-...` |
| `screenshots/langfuse_trace.png` | **Capture this session** |
| `screenshots/langfuse_tags.png` | **Capture this session** |
| `load_test/driver.py` | Phase 6 — already sends tags; no Phase 4 edit required |

---

## What to defer (but plan for)

| Item | When |
|------|------|
| Full eval trace tagging (`run_type=eval`) | Phase 5 — optional but helps debug failures |
| Load-test traces at 10+ RPS | Phase 6 — may need `LANGFUSE_DISABLED=1` + `trace-sample` |
| Correlating Langfuse latency with Grafana vLLM metrics | Phase 6 |
| Agent-value paragraph citing traces | Phase 7 `REPORT.md` |
| Re-capture `langfuse_*.png` after tuning | Optional if Phase 6 `trace-sample` shows better load-test tags |

---

## Relationship to later phases

| Phase | Dependency on Phase 4 |
|-------|------------------------|
| **5 (Evals)** | Optional: tag eval runs with `run_type=eval`, `batch_id=eval_baseline` for trace forensics on failures |
| **6 (SLOs)** | **Primary consumer of tags** — filter slow traces under `run_type=load_test`; compare `config_label` across tuning iterations |
| **7 (REPORT)** | Cite Langfuse as agent-level o11y complement to Grafana serving metrics; reference `langfuse_trace.png` |

---

## Time budget (single H100 session)

| Block | Duration | Notes |
|-------|----------|-------|
| Preflight + Langfuse UI | 5–10 min | Keys, health, one manual trace |
| 10-question smoke on 30B | 10–25 min | ~1–2 min per question depending on revise |
| Waterfall inspection + screenshots | 10–15 min | Pick best revise trace |
| **Total** | **~30–50 min** | Assumes Phases 1–3 already running |

If slot time is tight, run Phase 4 **immediately after Phase 3** while vLLM and agent are still up — same terminals, minimal context switch.

---

## Next phase

**Phase 5 (Evals)** — implement or run `evals/run_eval.py`, baseline against `evals/eval_set.jsonl`, record per-iteration pass rates to `results/eval_baseline.json`. Tag eval runs in Langfuse when convenient. See [README Phase 5](../README.md#phase-5-evals) and [`_local_dev/phase_5_plan.md`](_local_dev/phase_5_plan.md).
