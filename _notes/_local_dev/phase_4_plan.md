# Phase 4 Plan — Local Test Environment

This plan adapts [README.md Phase 4 (Agent o11y)](../README.md#phase-4-agent-o11y) for **local development on your machine** (WSL2 / laptop), not the cloud H100 VM. Per [assignment_remarks.md](assignment_remarks.md): wire Langfuse tracing locally first; **submission screenshots** (`screenshots/langfuse_trace.png`, `screenshots/langfuse_tags.png`) must come from the H100 + 30B run later.

---

## Goal

By the end of Phase 4 **locally** you should have:

- Langfuse receiving traces from every `POST /answer` when keys are in `.env`
- A trace waterfall showing **`generate_sql` → `execute` → `verify`** (and **`revise`** when the loop fires)
- LLM spans with prompt, response, latency, and token usage visible in the Langfuse UI
- Traces tagged with **metadata you will actually filter on in Phase 6** (slow-request diagnosis under load)
- **10 agent runs** logged in Langfuse, including at least one with a revise loop

**Final submission quality** (H100 only):

- Re-run the same smoke batch on `Qwen/Qwen3-30B-A3B-Instruct-2507`
- Capture `screenshots/langfuse_trace.png` (revise loop visible) and `screenshots/langfuse_tags.png` (tag columns visible in trace list)

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

### Already scaffolded (minimal code changes expected)

| Piece | File | Status |
|-------|------|--------|
| Langfuse `CallbackHandler` | `agent/server.py` | Created when `LANGFUSE_PUBLIC_KEY` + `LANGFUSE_SECRET_KEY` are set |
| Callback passed to graph | `agent/server.py` | `config={"callbacks": [_lf_handler], "metadata": req.tags}` |
| Request-level tags | `agent/server.py` | `AnswerRequest.tags: dict[str, str]` → LangGraph `metadata` |
| Langfuse stack | `docker-compose.yml` | Web on `:3001`, worker + Postgres + ClickHouse + Redis + MinIO |
| Env template | `.env.example` | `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST` |
| Dependency | `pyproject.toml` | `langfuse>=4.0,<5.0` |

**Import note:** README shows `from langfuse.callback import CallbackHandler`. This repo uses **Langfuse v4** with LangChain integration:

```python
from langfuse.langchain import CallbackHandler
```

That matches what `agent/server.py` already imports — do **not** change the handler unless traces fail to appear.

Graph node names in `agent/graph.py` (`generate_sql`, `execute`, `verify`, `revise`) are what Langfuse should show as span names in the waterfall.

### You implement / configure

| Piece | Where | Action |
|-------|-------|--------|
| Langfuse account + project keys | UI + `.env` | Sign up locally, copy public/secret keys |
| Restart agent after key change | Terminal | Handler is created at import time |
| Metadata tags on requests | `POST /answer` body | Pass `tags` dict on every run |
| 10-question smoke batch | curl or small script | Fire diverse questions through the agent |
| Screenshots | `screenshots/` | **Defer to H100** for submission artifacts |

No changes to `agent/graph.py` or `agent/prompts.py` are required for Phase 4 unless traces are missing spans (see Troubleshooting).

---

## Local vs H100 (what changes)

| README (VM / H100) | Local test phase |
|---|---|
| Traces from 30B agent runs | Same wiring; any OpenAI-compatible backend (0.6B vLLM, hosted API) |
| Submission screenshots | Validate UI + tags locally; **re-capture on H100** |
| Token counts / latency numbers for REPORT | Directionally useful locally; report **30B numbers** only |
| Phase 6 load-test tag filtering | Design tags now; load driver may need tags added in Phase 6 |

Phase 4 is fully doable off-GPU. README: *"Langfuse captures the LangGraph spans regardless of backend."*

---

## Prerequisites (local)

Assumes [Phase 0](phase_0_plan.md) and [Phase 3](phase_3_plan.md) local milestones:

- [x] `docker compose up -d` — Langfuse web reachable at http://localhost:3001
- [x] Phase 3 agent working — `POST /answer` returns SQL, rows, `history`
- [x] At least one local run with `iterations >= 2` (revise loop proven)
- [x] LLM backend running (local vLLM, hosted API, or CPU vLLM)

**Not required locally:** Grafana, H100, 30B model, Phase 5 eval runner.

---

## Step-by-step (local)

### Step 1 — Confirm Langfuse stack is up

```bash
cd /home/danar/repos/ai_performance/mlops/hw2_llm_inference_o11y
docker compose ps
```

Expect `langfuse-web`, `langfuse-worker`, and backing services **running**. First boot can take 1–2 minutes after dependencies are healthy.

```bash
docker compose logs -f langfuse-web   # if UI is slow to load
```

Open http://localhost:3001 — login page should load.

---

### Step 2 — Create project and API keys

1. Sign up with any email (local instance — no real verification).
2. Create or select org/project (compose may pre-seed **Course / Default**).
3. Go to **Project Settings → API Keys**.
4. Create a key pair; copy **public** and **secret** keys.

---

### Step 3 — Add keys to `.env`

From `.env.example`:

```bash
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
LANGFUSE_HOST=http://localhost:3001
```

**Restart the agent** after editing `.env` — the handler is initialized at module load:

```bash
# stop existing uvicorn, then:
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

**Sanity check:** if keys are wrong or Langfuse is down, `POST /answer` should **fail loudly** (handler errors are not swallowed in `server.py`).

---

### Step 4 — Confirm tracing with one tagged request

Use a question that often triggers revise on a stand-in model (e.g. `formula_1` coordinates):

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
      "batch_id": "local-smoke-001"
    }
  }' | jq .
```

In Langfuse UI → **Tracing** → latest trace:

| Check | Expected |
|-------|----------|
| Trace exists | One new trace per `/answer` call |
| Span tree | Nested spans for graph nodes |
| LLM spans | Under `generate_sql`, `verify`, optionally `revise` |
| Span detail | Prompt input, model output, latency, token usage |
| Metadata | `run_type`, `source`, `db_id`, `batch_id` visible on trace |

If you only see a flat trace with no node names, see Troubleshooting — but **do not** duplicate the handler inside `graph.py`; `server.py` already attaches it at invoke time.

---

### Step 5 — Fire 10 questions through the agent

README asks for **10 questions**. Pick a mix from `evals/eval_set.jsonl` — include at least one that triggered revise in Phase 3.

**Suggested batch** (first 10 lines of eval set, diverse `db_id`):

| # | `db_id` | Notes |
|---|---------|-------|
| 1 | `formula_1` | Often triggers revise locally |
| 2 | `superhero` | Simple count |
| 3 | `california_schools` | ORDER BY + LIMIT |
| 4 | `financial` | Join + filter |
| 5 | `formula_1` | Aggregation |
| 6 | `formula_1` | Status filter |
| 7 | `student_club` | Date parsing |
| 8 | `california_schools` | Multi-column address |
| 9 | `toxicology` | Percentage calc |
| 10 | `codebase_community` | Date filter |

**Loop example** (adjust paths if needed):

```bash
BATCH_ID="local-smoke-$(date +%Y%m%d-%H%M)"
i=0
while IFS= read -r line; do
  i=$((i + 1))
  [ "$i" -gt 10 ] && break
  q=$(echo "$line" | jq -r '.question')
  db=$(echo "$line" | jq -r '.db_id')
  curl -s -X POST http://localhost:8001/answer \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg q "$q" --arg db "$db" --arg batch "$BATCH_ID" --argjson n "$i" \
      '{question: $q, db: $db, tags: {
        run_type: "smoke",
        source: "phase4_batch",
        db_id: $db,
        batch_id: $batch,
        seq: ($n | tostring)
      }}')" > /dev/null
  echo "sent $i/$db"
done < evals/eval_set.jsonl
```

Wait a few seconds for Langfuse worker ingestion, then refresh the trace list.

---

### Step 6 — Inspect waterfall (generate_sql / verify / revise)

1. Open **Tracing** in Langfuse.
2. Pick a trace where the agent response had `iterations >= 2`.
3. Expand the span tree. You should see something like:

```
Trace (POST /answer or LangGraph run)
├── attach_schema
├── generate_sql
│   └── ChatOpenAI / LLM generation
├── execute
├── verify
│   └── ChatOpenAI / LLM generation
├── revise          ← only when verify failed
│   └── ChatOpenAI / LLM generation
├── execute
└── verify
```

4. Click each LLM span — confirm **input**, **output**, **latency**, **tokens** (prompt / completion / total).

**Local:** screenshot optional for your own notes.

**H100 submission:** save as `screenshots/langfuse_trace.png` — choose a trace where **revise** is visible in the tree.

---

### Step 7 — Tag traces for Phase 6

Phase 6 is load testing and diagnosis (*"why was this request slow?"*). Tags must be **filterable in the Langfuse trace list** and **consistent** across smoke, eval, and load runs.

Recommended tag schema (all string values):

| Key | Example values | Use in Phase 6 |
|-----|----------------|----------------|
| `run_type` | `smoke`, `eval`, `load_test` | Separate dev noise from SLO runs |
| `batch_id` | `local-smoke-20250616`, `slo-baseline-v3` | Group a run session |
| `db_id` | `formula_1`, `superhero`, … | Compare latency by database |
| `source` | `phase4_manual`, `phase4_batch`, `run_eval`, `load_driver` | Know which client fired the request |
| `config_label` | `local-0.6b`, `h100-30b-baseline`, `h100-30b-tuned` | Tie traces to vLLM config iterations |

**Rules:**

- Pass the same keys on **every** `/answer` call in a given experiment — do not tag ad hoc.
- Use `batch_id` so Phase 6 load-test traces are one filter away from smoke tests.
- When you move to H100, change `config_label` — do not mix 0.6B and 30B traces under the same label.

`load_test/driver.py` does **not** send tags today. For Phase 6 you will likely extend it to add `run_type=load_test` and `batch_id=...`. Phase 4 proves the `tags` → Langfuse metadata path works.

**H100 submission:** Langfuse trace list with tag columns visible → `screenshots/langfuse_tags.png`.

---

## Phase 4 completion checklist

### Local test phase (now)

- [ ] Langfuse UI loads at http://localhost:3001
- [ ] Project created; `LANGFUSE_PUBLIC_KEY` and `LANGFUSE_SECRET_KEY` in `.env`
- [ ] `LANGFUSE_HOST=http://localhost:3001` set
- [ ] Agent restarted after adding keys
- [ ] One manual `POST /answer` produces a trace in Langfuse within ~30s
- [ ] Trace waterfall shows `generate_sql`, `verify`, and `execute` spans
- [ ] At least one trace shows **`revise`** in the span tree
- [ ] LLM spans show prompt, response, latency, token counts
- [ ] 10 questions fired with consistent `tags` (`run_type`, `batch_id`, `db_id`, …)
- [ ] Trace list filterable by at least one tag (e.g. `run_type = smoke`)

### H100 / submission (later)

- [ ] Re-run smoke batch against 30B with `config_label=h100-30b-baseline` (or similar)
- [ ] `screenshots/langfuse_trace.png` — revise loop visible
- [ ] `screenshots/langfuse_tags.png` — metadata tags visible in trace list
- [ ] Tags schema reused in Phase 5 eval runs (`run_type=eval`) and Phase 6 load test (`run_type=load_test`)

---

## What to defer until H100

- Submission screenshots under `screenshots/`
- Token/latency numbers quoted in `REPORT.md`
- Correlating Langfuse trace latency with Grafana vLLM metrics under real concurrency (Phase 6)
- Ensuring trace quality at 10+ RPS (flush/backpressure behavior at scale)

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| No traces at all | Keys missing or agent not restarted | Set `.env` keys; restart uvicorn |
| `POST /answer` 500 after adding keys | Wrong host/keys; Langfuse down | Check `LANGFUSE_HOST`; `docker compose ps`; read exception `detail` |
| Traces appear but no node names | Old agent code / graph not invoked with callbacks | Confirm `server.py` passes `callbacks` in `graph.invoke` config |
| Flat trace, no LLM children | Handler not LangChain-compatible | Keep `langfuse.langchain.CallbackHandler` (v4) |
| Metadata tags missing | Empty `tags` in request | Include `tags` in JSON body; check trace **Metadata** panel |
| Traces delayed | Worker backlog | Wait 10–30s; check `langfuse-worker` logs |
| Langfuse UI blank / 502 | Stack still starting | `docker compose logs -f langfuse-web`; wait for Postgres/ClickHouse |
| Cannot find revise trace | Verifier too lenient on stand-in model | Re-run a question that returned `iterations >= 2` in Phase 3; or temporarily tighten verify for one test |
| WSL2 cannot reach `:3001` | Port not forwarded / compose not up | `docker compose up -d`; curl http://localhost:3001 |

---

## File touch map

| File | Action |
|------|--------|
| `.env` | Add `LANGFUSE_*` keys |
| `agent/server.py` | **No changes expected** — already wires handler + metadata |
| `agent/graph.py` | **No changes expected** — node names drive span labels |
| `evals/eval_set.jsonl` | Read-only — source for 10 smoke questions |
| `load_test/driver.py` | Optional later — add `tags` for Phase 6 load runs |
| `screenshots/langfuse_*.png` | Capture on H100 for submission |

---

## Relationship to later phases

| Phase | Dependency on Phase 4 |
|-------|------------------------|
| **5 (Evals)** | Optional: tag eval runs with `run_type=eval`, `batch_id=eval_baseline` for trace forensics on failures |
| **6 (SLOs)** | **Primary consumer of tags** — filter slow traces under `run_type=load_test`; compare `config_label` across tuning iterations |
| **7 (REPORT)** | Cite Langfuse as agent-level o11y complement to Grafana serving metrics |

After Phase 4 locally, you can run Phase 5 eval harness end-to-end with tracing on — pass rates still need 30B for reporting.

---

## Next phase

**Phase 5 (Evals)** — implement `evals/run_eval.py`, run baseline against `evals/eval_set.jsonl`, record per-iteration pass rates to `results/eval_baseline.json`. See [README Phase 5](../README.md#phase-5-evals).
