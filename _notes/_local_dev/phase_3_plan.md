# Phase 3 Plan — Local Test Environment

This plan adapts [README.md Phase 3 (Agent)](../README.md#phase-3-agent) for **local development on your machine** (WSL2 / laptop), not the cloud H100 VM. Per [assignment_remarks.md](assignment_remarks.md): build and debug the LangGraph agent locally first; reserve the H100 for final prompt tuning and submission-quality runs.

---

## Goal

By the end of Phase 3 **locally** you should have:

- A working **verify → revise** loop in `agent/graph.py` with an iteration cap
- Prompts in `agent/prompts.py` that catch obvious failures (SQL error, zero rows, wrong columns)
- Agent server at `http://localhost:8001` returning SQL, rows, and per-iteration `history`
- **5 interactive tests** from `evals/eval_set.jsonl`, with **at least one** triggering a revise

**Final submission quality** (H100 only):

- Prompt tuning against `Qwen/Qwen3-30B-A3B-Instruct-2507` (behavior differs from stand-in models)
- Re-run the same 5 questions on 30B; confirm revise still fires when it should

---

## What you are building (context)

Phase 3 is a **self-consistency inspired text-to-SQL agent**: generate SQL, execute against BIRD sqlite, verify plausibility, revise if not. The graph shape is fixed; your work is prompts + three nodes + the router.

```
question + schema
       │
       ▼
┌─────────────────┐
│ generate_sql    │  ── LLM call #1
└─────────────────┘
       │
       ▼
┌─────────────────┐
│ execute         │  (provided)
└─────────────────┘
       │
       ▼
┌─────────────────┐
│ verify          │  ── LLM call #2  →  {ok: bool, issue: str}
└─────────────────┘
       │
ok=true├──► END (return SQL + rows)
       │
ok=false├──► ┌─────────────────┐
             │ revise          │  ── LLM call #3
             └─────────────────┘
                    │
                    ▼
             execute → verify (loop, capped)
```

### Already scaffolded (do not rewire)

| Piece | File | Status |
|-------|------|--------|
| Graph wiring | `agent/graph.py` | `START → attach_schema → generate_sql → execute → verify` + conditional edge to `revise → execute` |
| `generate_sql_node` | `agent/graph.py` | Worked example — copy this pattern |
| `execute_node` | `agent/graph.py` | Complete |
| Schema rendering | `agent/schema.py` | Complete |
| SQL execution | `agent/execution.py` | Complete (`ExecutionResult.render()` for prompts) |
| HTTP server | `agent/server.py` | Complete (`POST /answer`, `GET /health`) |
| LLM client | `agent/graph.py` | `ChatOpenAI` → `VLLM_BASE_URL` / `VLLM_MODEL` / `OPENAI_API_KEY` |

### You implement

| Piece | File | Returns |
|-------|------|---------|
| `GENERATE_SQL_*` prompts | `agent/prompts.py` | (consumed by existing node) |
| `VERIFY_*` prompts | `agent/prompts.py` | |
| `REVISE_*` prompts | `agent/prompts.py` | |
| `verify_node` | `agent/graph.py` | `{"verify_ok": bool, "verify_issue": str}` |
| `revise_node` | `agent/graph.py` | `{"sql": str, "iteration": +1, "history": [...]}` |
| `route_after_verify` | `agent/graph.py` | `"revise"` or `"end"` |

`MAX_ITERATIONS` is already `3` in `agent/graph.py` (README allows 3–5; tune locally, finalize on H100).

---

## Local vs H100 (what changes)

| README (VM / H100) | Local test phase |
|---|---|
| Final prompt tuning on `Qwen3-30B-A3B` | Wire graph + draft prompts on **any** OpenAI-compatible backend |
| Reported eval pass rates / SLO | Not meaningful locally — validate **loop behavior** only |
| Agent quality bar for leadership demo | Smoke-test: graph completes, revise fires, rows return |

### Recommended local LLM backend (pick one)

| Option | Good for Phase 3? | Notes |
|--------|-------------------|-------|
| **Local vLLM + `Qwen/Qwen3-0.6B`** via `scripts/start_vllm_local.sh` | Yes (recommended) | Same API as prod; slow but exercises full stack. Set `.env` `VLLM_MODEL=Qwen/Qwen3-0.6B`. |
| **Hosted OpenAI-compatible API** (`.env` overrides) | Yes | Fast iteration without local vLLM. No `/metrics` — fine for Phase 3. |
| **H100 + 30B** | Optional early tune | Only if you already have a slot; not required to *build* Phase 3. |

`.env` alignment (local vLLM):

```bash
VLLM_MODEL=Qwen/Qwen3-0.6B   # must match scripts/start_vllm_local.sh MODEL=
# VLLM_BASE_URL defaults to http://localhost:8000/v1 in agent/graph.py
```

Hosted API shortcut (uncomment in `.env.example`):

```bash
VLLM_BASE_URL=https://api.openai.com/v1
VLLM_MODEL=gpt-4o-mini
OPENAI_API_KEY=sk-...
```

---

## Prerequisites (local)

Assumes [Phase 0](phase_0_plan.md) is done:

- [x] `uv sync`
- [x] `.env` from `.env.example`
- [x] `data/bird/*.sqlite` via `uv run python scripts/load_data.py`

For local Phase 3 you need **one** of:

- [x] vLLM stand-in on `:8000` (`bash scripts/start_vllm_local.sh`), **or**
- [x] Hosted API keys in `.env`

Phase 2 Grafana is **not** required for Phase 3. Langfuse keys are **Phase 4** — `agent/server.py` already loads them if present; Phase 3 works with zero Langfuse config.

---

## Implementation plan

Work in this order: prompts first (they drive node behavior), then nodes, then router, then HTTP tests.

### Step 1 — `GENERATE_SQL_*` prompts (`agent/prompts.py`)

`generate_sql_node` is already wired. Fill:

- `GENERATE_SQL_SYSTEM` — role: SQLite expert for BIRD; output **only** SQL (or a single ` ```sql ` block).
- `GENERATE_SQL_USER` — must keep placeholders `{schema}` and `{question}`.

**Guidelines:**

- Paste full `CREATE TABLE` schema (already rendered with quoted identifiers).
- Instruct: SQLite dialect, double-quote identifiers with spaces/reserved words, `JOIN` when needed, no DML/DDL.
- Ask for one query answering the question exactly.

**Local smoke:** after prompts, invoke graph once (see Step 6) — you should get non-empty SQL and either rows or a SQL error in `execution`.

---

### Step 2 — `VERIFY_*` prompts + `verify_node`

**Verifier job:** given question, SQL, and `execution.render()`, decide if the result **plausibly** answers the question.

**Target failure modes** (from README):

| Signal | `verify_ok` | Example `verify_issue` |
|--------|-------------|------------------------|
| SQL execution error | `false` | `"SQL error: no such column: foo"` |
| Zero rows when question expects data | `false` | `"Question asks for a count/list but 0 rows returned"` |
| Columns don't match question | `false` | `"Question asks for coordinates; result has only names"` |
| Plausible answer | `true` | `""` |

**Prompt design:**

- `VERIFY_SYSTEM` — strict JSON-only responder: `{"ok": true/false, "issue": "..."}`.
- `VERIFY_USER` — include `{question}`, `{sql}`, `{execution_result}` (or similar placeholders your node passes).

**`verify_node` implementation** (mirror `generate_sql_node`):

```python
response = llm().invoke([...])
# Parse JSON defensively: strip fences, regex extract {...}, json.loads
return {"verify_ok": ok, "verify_issue": issue}
```

**Parsing helper** (inline in `graph.py` or small `_parse_json_object(text)`):

- Try `json.loads` on full content
- Else extract first `{...}` with regex
- On parse failure: treat as `verify_ok=False`, `verify_issue="could not parse verifier output"`

Append to `history`: `{"node": "verify", "ok": ..., "issue": ...}`.

**Optional hard rules before LLM** (cheap, reliable locally):

- If `not state.execution.ok` → skip LLM, return `verify_ok=False`, `verify_issue=state.execution.error`
- Keeps revise loop working even if verifier prompt is weak

---

### Step 3 — `REVISE_*` prompts + `revise_node`

**Reviser job:** given question, schema, failed SQL, execution result, and verifier complaint → emit corrected SQL.

**Prompt design:**

- `REVISE_SYSTEM` — fix SQL only; same output rules as generate.
- `REVISE_USER` — include `{schema}`, `{question}`, `{sql}`, `{execution_result}`, `{issue}`.

**`revise_node` implementation** (same shape as `generate_sql_node`):

```python
response = llm().invoke([...])
sql = _extract_sql(response.content)
return {
    "sql": sql,
    "iteration": state.iteration + 1,
    "history": state.history + [{"node": "revise", "sql": sql, "issue": state.verify_issue}],
}
```

Reuse `_extract_sql` for markdown fences.

---

### Step 4 — `route_after_verify`

Replace `NotImplementedError` with:

```python
def route_after_verify(state: AgentState) -> str:
    if state.verify_ok or state.iteration >= MAX_ITERATIONS:
        return "end"
    return "revise"
```

**Iteration semantics** (already in scaffold):

- `iteration` increments in `generate_sql_node` and `revise_node` (not in `verify`).
- First pass: `generate_sql` → `iteration=1`. If verify fails and cap is 3, you get at most **2 revise attempts** (generate + 2 revises = 3 LLM SQL-producing calls).

No graph wiring changes needed — conditional edges are already:

```python
g.add_conditional_edges("verify", route_after_verify, {"revise": "revise", "end": END})
g.add_edge("revise", "execute")
```

---

### Step 5 — Start the agent server

Terminal 1 — LLM backend (if using local vLLM):

```bash
cd /home/danar/repos/ai_performance/mlops/hw2_llm_inference_o11y
bash scripts/start_vllm_local.sh
```

Terminal 2 — agent:

```bash
cd /home/danar/repos/ai_performance/mlops/hw2_llm_inference_o11y
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

**Health check:**

```bash
curl -s http://localhost:8001/health
```

---

### Step 6 — Interactive tests (5 questions from eval set)

Pick **5** lines from `evals/eval_set.jsonl` with mixed `db_id` and difficulty. Suggested set for local dev:

| # | `db_id` | Question (abbrev.) | Why include |
|---|---------|-------------------|-------------|
| 1 | `superhero` | Super Strength count | Simple; good first pass |
| 2 | `financial` | Male clients in Hl.m. Praha | Single-table filter + join |
| 3 | `formula_1` | Australian GP circuit coordinates | Join; stand-in model often gets columns wrong → revise |
| 4 | `california_schools` | Top 5 schools by enrollment | `ORDER BY` + `LIMIT`; easy to verify wrong sort |
| 5 | `codebase_community` | Commentator badges in 2014 | Date parsing; common stand-in failure |

**HTTP test** (from README):

```bash
curl -s -X POST http://localhost:8001/answer \
  -H "Content-Type: application/json" \
  -d '{"question": "How many superheroes have the super power of \"Super Strength\"?", "db": "superhero"}' \
  | jq .
```

**Inspect response fields:**

| Field | What to check |
|-------|----------------|
| `ok` | `true` when execution succeeded |
| `sql` | Final SQL after any revises |
| `rows` | Non-null when `ok` |
| `iterations` | `1` = no revise; `2+` = loop ran |
| `history` | Entries for `generate_sql`, `verify`, optionally `revise` |
| `error` | Set when execution failed at end |

**Prove revise fired:** at least one run with `iterations >= 2` and a `revise` entry in `history`.

**Optional — direct graph invoke** (no HTTP, faster debug):

```bash
uv run python -c "
from agent.graph import graph, AgentState
s = AgentState(question='...', db_id='superhero')
out = graph.invoke(s)
print('iter', out['iteration'], 'verify_ok', out['verify_ok'])
print('history', out['history'])
"
```

---

### Step 7 — Tune prompts locally (iterate)

Local stand-in models **will** produce bad SQL — that is useful for testing the revise loop.

| Symptom | Likely fix |
|---------|------------|
| Verifier always `ok=true` on garbage | Strengthen VERIFY prompts; add execution-error short-circuit |
| Verifier always `ok=false` on good SQL | Soften “zero rows” rule; ask model to allow empty if question allows |
| Revise repeats same mistake | Include full schema + prior SQL + error in REVISE_USER |
| Loop hits cap, still wrong | Expected on 0.6B; note for H100 retune |
| `NotImplementedError` | Finish `verify_node`, `revise_node`, `route_after_verify` |
| 500 from `/answer` | Read `detail`; often LLM connection or graph exception |

Keep a scratch log: question → iterations → final ok → notes. Reuse for H100 comparison.

---

## Phase 3 completion checklist

### Local test phase (now)

- [ ] `GENERATE_SQL_SYSTEM` / `GENERATE_SQL_USER` filled in `agent/prompts.py`
- [ ] `VERIFY_SYSTEM` / `VERIFY_USER` filled in `agent/prompts.py`
- [ ] `REVISE_SYSTEM` / `REVISE_USER` filled in `agent/prompts.py`
- [ ] `verify_node` implemented with defensive JSON parse (+ optional execution-error shortcut)
- [ ] `revise_node` implemented (mirrors `generate_sql_node`)
- [ ] `route_after_verify` returns `"end"` on `verify_ok` or `iteration >= MAX_ITERATIONS`
- [ ] Agent server running on `http://localhost:8001`
- [ ] `GET /health` returns `{"status":"ok"}`
- [ ] 5 eval questions tested via `POST /answer`
- [ ] At least **one** test shows `iterations >= 2` and `history` contains `"node": "revise"`
- [ ] At least **one** test returns `ok: true` with non-empty `rows` (best effort on stand-in model)

### H100 / submission (later)

- [ ] `.env` reset to `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507` + local vLLM URL
- [ ] Re-run same 5 questions; adjust prompts for 30B tokenization/behavior
- [ ] Confirm revise still adds value (not no-op loop) — full signal in Phase 5 per-iteration pass rates

---

## What to defer until H100

- Final prompt quality and execution-accuracy pass rates
- Choosing final `MAX_ITERATIONS` (3 vs 5) based on eval data
- Langfuse traces and screenshots (Phase 4)
- Correlating agent latency with vLLM Grafana panels under real load (Phase 6)
- Any numbers reported in `REPORT.md` for agent quality

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Connection refused` on `/answer` | Agent not running | Start uvicorn on `:8001` |
| `Connection error` / timeout in graph | vLLM down or wrong `VLLM_BASE_URL` | Start `start_vllm_local.sh` or fix `.env` |
| `404` / model not found from LLM | `VLLM_MODEL` mismatch | Match `.env` to served model id (`/v1/models`) |
| `FileNotFoundError` for DB | Data not loaded | `uv run python scripts/load_data.py` |
| Empty `sql` | Model returned prose only | Tighten GENERATE/REVISE output format; check `_extract_sql` |
| `iterations` always `1` | Verifier too lenient or first SQL always “ok” | Harden verify; test with intentionally bad SQL |
| `iterations` hits cap, `ok: false` | Stand-in model too weak | Expected locally; verify loop mechanics still work |
| JSON parse errors in verify | Model wrapped JSON in fences | Harden `_parse_json_object`; retry with stricter VERIFY_SYSTEM |
| SQL syntax errors on quoted columns | Model unquoted reserved names | Schema already uses `"quoted"` ids — remind in prompts |

---

## File touch map

| File | Action |
|------|--------|
| `agent/prompts.py` | Fill all six prompt strings |
| `agent/graph.py` | Implement `verify_node`, `revise_node`, `route_after_verify`; optional JSON helper |
| `.env` | Ensure `VLLM_MODEL` / API overrides match backend |
| `agent/server.py` | No changes expected |
| `agent/execution.py`, `agent/schema.py` | No changes expected |

---

## Relationship to later phases

| Phase | Dependency on Phase 3 |
|-------|------------------------|
| **4 (Langfuse)** | `server.py` already passes `CallbackHandler` when keys exist — run agent after Phase 3 |
| **5 (Evals)** | `evals/run_eval.py` calls `POST /answer`; needs working agent + iteration stats |
| **6 (SLO)** | Load test hits agent `:8001`; 2–3 LLM calls per request — revisit Phase 1 vLLM config |
| **2 (Grafana)** | Optional now: fire `/answer` burst and watch vLLM metrics move |

After Phase 3 locally, **revisit Phase 1** with real prompt sizes (schema + verify + revise contexts) before H100 load testing.

---

## Next phase

**Phase 4 (Agent o11y)** — add Langfuse keys to `.env`, confirm traces show `generate_sql` / `verify` / `revise` waterfall. See [README Phase 4](../README.md#phase-4-agent-o11y).
