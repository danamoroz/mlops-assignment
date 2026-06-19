# Phase 3 Plan — Nebius H100 VM (Final / Submission Environment)

This plan adapts [README.md Phase 3 (Agent)](../README.md#phase-3-agent) for the **Nebius H100 slot**. It builds on what we already validated locally in [`_local_dev/phase_3_plan.md`](_local_dev/phase_3_plan.md). Local Phase 3 implementation is done in `agent/graph.py` and `agent/prompts.py`; this session **tunes prompts against 30B**, proves the verify→revise loop on submission hardware, and records a comparison log for Phase 5 evals.

Per [assignment_remarks.md](_local_dev/assignment_remarks.md): build and debug the LangGraph agent locally first; reserve the H100 for final prompt tuning and submission-quality runs.

---

## Goal

By the end of Phase 3 on Nebius you should have:

- Agent server at **`http://localhost:8001`** backed by **`Qwen/Qwen3-30B-A3B-Instruct-2507`** on `:8000`
- **`verify → revise`** loop firing when it should, capped at `MAX_ITERATIONS` (default **3**)
- **5 interactive tests** from `evals/eval_set.jsonl` re-run on 30B — at least **one** with `iterations >= 2` and a `revise` entry in `history`
- At least **one** test returning `ok: true` with non-empty `rows` on 30B
- Prompts tuned for 30B tokenization/behavior (verifier not too lenient, reviser not a no-op)
- Scratch log: local stand-in results vs H100 30B (same 5 questions) — reuse in Phase 5 / `REPORT.md`

**Out of scope for Phase 3** (later phases): Langfuse screenshots (Phase 4), full 30-question eval pass rates (Phase 5), SLO load test (Phase 6), `REPORT.md` agent-value paragraph (Phase 7). Phase 3 only needs a working agent and proof the revise loop adds signal on 30B.

---

## What you are building (context)

Phase 3 is a **self-consistency inspired text-to-SQL agent**: generate SQL, execute against BIRD sqlite, verify plausibility, revise if not. The graph shape is fixed; local work implemented prompts + three nodes + the router.

```
question + schema
       │
       ▼
┌─────────────────┐
│ generate_sql    │  ── vLLM call #1
└─────────────────┘
       │
       ▼
┌─────────────────┐
│ execute         │  (provided)
└─────────────────┘
       │
       ▼
┌─────────────────┐
│ verify          │  ── vLLM call #2  →  {ok: bool, issue: str}
└─────────────────┘
       │
ok=true├──► END (return SQL + rows)
       │
ok=false├──► ┌─────────────────┐
             │ revise          │  ── vLLM call #3
             └─────────────────┘
                    │
                    ▼
             execute → verify (loop, capped)
```

**Iteration semantics** (already wired):

- `iteration` increments in `generate_sql_node` and `revise_node` (not in `verify`)
- First pass: `generate_sql` → `iteration=1`. With `MAX_ITERATIONS=3`, at most **2 revise attempts** (1 generate + 2 revises = 3 SQL-producing LLM calls)
- `route_after_verify` ends on `verify_ok` **or** `iteration >= MAX_ITERATIONS`

---

## What we already have locally (don't re-invent)

Implemented on WSL2 / laptop (2026-06), per [`phase_3_plan.md`](_local_dev/phase_3_plan.md):

| Item | Local status | On Nebius |
|------|--------------|-----------|
| Graph wiring | `START → attach_schema → generate_sql → execute → verify` + conditional `revise → execute` | **No rewiring** — use as-is |
| `generate_sql_node` | Worked example + prompts filled | Re-test on 30B only |
| `verify_node` | LLM JSON parse + execution-error short-circuit | Tune VERIFY prompts if 30B too lenient/strict |
| `revise_node` | Mirrors generate; includes `prior_sql`, `issue` | Tune REVISE prompts if revise repeats mistakes |
| `route_after_verify` | `"end"` on `verify_ok` or cap; else `"revise"` | Confirm cap behavior on 30B |
| Prompts (`agent/prompts.py`) | All six strings filled (GENERATE / VERIFY / REVISE) | **Primary H100 work** — iterate here |
| Qwen3 helpers | `enable_thinking: False`, `_strip_thinking`, `_parse_json_object` | Critical on 30B — verify no thinking tags leak into SQL/JSON |
| HTTP server | `agent/server.py` — `POST /answer`, `GET /health` | Start on `:8001` |
| Schema + execution | `agent/schema.py`, `agent/execution.py` | No changes expected |
| `MAX_ITERATIONS` | Default `3` via env (`graph.py`) | Decide 3 vs 5 after 30B smoke (defer final choice to Phase 5/6) |

**Do not copy local-only env to H100:**

- `VLLM_MODEL=Qwen/Qwen3-0.6B` — local stand-in only
- Path A hosted API overrides (`VLLM_BASE_URL=https://api...`) — comment out on H100; agent must hit local vLLM on `:8000`
- `start_vllm_local.sh` flags (`VLLM_USE_V1=0`, `--enforce-eager`, etc.)

On H100, `.env` should have:

```bash
VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507
# VLLM_BASE_URL=...   # leave commented — defaults to http://localhost:8000/v1
```

---

## Local vs Nebius (what changes)

| Local test (WSL / 0.6B or hosted API) | Nebius H100 VM |
|---------------------------------------|----------------|
| Loop **mechanics** validation | Loop **quality** on submission model |
| Verifier may fire often on weak SQL | 30B first-pass SQL often better — revise may fire less |
| Latency per `/answer` not meaningful | First real 2–3 call latency readings (~seconds, not minutes) |
| `iterations` hits cap with `ok: false` common | Expect more `ok: true` on first or second pass |
| Prompt drafts tuned for stand-in failures | Retune VERIFY/REVISE for 30B false positives/negatives |
| No submission artifact for Phase 3 | Scratch log + optional Grafana `/answer` burst (helps Phase 6) |

**Key behavioral shift on 30B:** the verifier may become the bottleneck — too strict → unnecessary revise loops; too lenient → `iterations` always `1` and Phase 5 shows flat per-iteration pass rates. Tune on H100 until at least one question still revises *and* at least one first-pass answer is accepted.

---

## Prerequisites (Nebius VM)

Confirm before starting the agent (most come from [Phase 0](final_phase_0.md) + [Phase 1](final_phase_1.md)):

- [ ] **Phase 1 complete** — 30B vLLM on `:8000`, `curl http://localhost:8000/v1/models` shows 30B id
- [ ] **`data/bird/*.sqlite`** — 11 BIRD databases loaded (`uv run python scripts/load_data.py` if missing)
- [ ] **`.env`** — `VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507`, Path A overrides **commented out**
- [ ] **Port 8001 free** — `ss -tlnp | grep 8001` returns nothing
- [ ] **Port forward** — `:8001` from laptop if testing via curl remotely
- [ ] **`uv sync`** — LangGraph + FastAPI deps present

**Optional but helpful:** Phase 2 Grafana running — watch prefill/queue panels while firing `/answer` (schema-heavy prompts ~1.5–3K tokens).

**VM sanity checklist:**

```bash
cd ~/mlops-assignment
curl -sf http://localhost:8000/health && echo "vLLM ok"
grep -E '^(VLLM_MODEL|HF_TOKEN)=' .env
ls data/bird/*.sqlite | wc -l   # expect 11
ss -tlnp | grep 8001 || echo "port 8001 free"
```

---

## Execution steps

### Step 0 — Confirm vLLM is warm (do not restart if Phase 1/2 left it running)

Restarting 30B costs 30–90 minutes. If vLLM is already healthy, skip straight to the agent.

```bash
curl -s http://localhost:8000/v1/models | jq -r '.data[0].id'
curl -s http://localhost:8000/health
```

Expect model id `Qwen/Qwen3-30B-A3B-Instruct-2507`.

If vLLM is down:

```bash
bash scripts/start_vllm.sh
# wait for "Uvicorn running on http://0.0.0.0:8000"
```

---

### Step 1 — Align agent env with local vLLM

```bash
cd ~/mlops-assignment
set -a && source .env && set +a
echo "model=$VLLM_MODEL base=${VLLM_BASE_URL:-http://localhost:8000/v1}"
```

Confirm:

- `VLLM_MODEL` matches served model id exactly
- No `VLLM_BASE_URL` override pointing at a hosted API
- `OPENAI_API_KEY` / `NEBIUS_API_KEY` unset or irrelevant (vLLM ignores key)

**Qwen3 on 30B:** `agent/graph.py` already passes `chat_template_kwargs: {enable_thinking: false}` when model name contains `qwen3`. Do not remove this — thinking blocks break SQL extraction and JSON verify parsing.

---

### Step 2 — Start the agent server (dedicated terminal)

```bash
cd ~/mlops-assignment
set -a && source .env && set +a
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

Keep this terminal open for the rest of Phase 3.

**Health check:**

```bash
curl -s http://localhost:8001/health | jq .
```

Expect `{"status": "ok", "langfuse_enabled": true|false}`. Langfuse is optional for Phase 3 acceptance; keys in `.env` are fine for an early Phase 4 smoke.

---

### Step 3 — Interactive tests (5 questions from eval set)

Use the **same five questions** as Phase 1 probes and the local Phase 3 plan — enables apples-to-apples comparison.

| # | `db_id` | Question (abbrev.) | Why include |
|---|---------|-------------------|-------------|
| 1 | `superhero` | Super Strength count | Simple aggregate; good first pass |
| 2 | `financial` | Male clients in Hl.m. Praha | Filter + district string |
| 3 | `formula_1` | Australian GP circuit coordinates | Join; often triggers revise locally |
| 4 | `california_schools` | Top 5 schools by enrollment (NCES id) | `ORDER BY` + `LIMIT` |
| 5 | `codebase_community` | Commentator badges in 2014 | Date filter |

**HTTP test** (from README):

```bash
curl -s -X POST http://localhost:8001/answer \
  -H "Content-Type: application/json" \
  -d '{"question": "How many superheroes have the super power of \"Super Strength\"?", "db": "superhero"}' \
  | jq '{ok, iterations, sql, error, history: [.history[] | {node, ok: .ok // empty, issue: .issue // empty, sql: .sql // empty}]}'
```

Repeat for all five rows. Full question strings match `scripts/probe_vllm_sql.sh`.

**Inspect response fields:**

| Field | What to check on 30B |
|-------|----------------------|
| `ok` | `true` when execution succeeded **and** verifier accepted |
| `sql` | Final SQL after any revises — plausible tables/columns for that `db_id` |
| `rows` | Non-null when `ok`; sensible values |
| `iterations` | `1` = no revise; `2+` = loop ran |
| `history` | `generate_sql`, `verify`, optionally `revise` |
| `error` | Set when execution failed or verifier rejected at cap |

**Prove revise fired (submission requirement):** at least one run with `iterations >= 2` and `"node": "revise"` in `history`.

**Batch helper** (optional — also seeds Langfuse for Phase 4):

```bash
uv run python scripts/phase4_smoke.py --count 5 --batch-id h100-phase3-smoke --source phase3_h100
```

---

### Step 4 — Record scratch log (local vs H100)

For each of the 5 questions, note:

| Question # | Local `iterations` | H100 `iterations` | H100 `ok` | Revise helped? | Prompt note |
|------------|-------------------|-------------------|-----------|----------------|-------------|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |

Save under `_notes/` or a scratch file — Phase 5 `pass_rate_by_iteration` and Phase 7 agent-value paragraph reference this.

**Optional direct graph invoke** (bypass HTTP, faster prompt iteration):

```bash
uv run python -c "
from agent.graph import graph, AgentState
s = AgentState(
    question='What is the coordinates location of the circuits for Australian grand prix?',
    db_id='formula_1',
)
out = graph.invoke(s)
print('iter', out['iteration'], 'verify_ok', out['verify_ok'])
for h in out['history']:
    print(h)
"
```

---

### Step 5 — Tune prompts on 30B (primary H100 work)

Edit `agent/prompts.py` only — nodes in `graph.py` should stay stable unless parsing breaks.

| Symptom on 30B | Likely fix |
|----------------|------------|
| `iterations` always `1` but SQL wrong | Strengthen `VERIFY_SYSTEM` — zero rows, wrong columns, duplicate rows |
| `iterations` always `1` and SQL correct | OK — but confirm verifier isn't blindly passing garbage on harder questions |
| Verifier rejects good SQL | Soften zero-row rule; allow empty when question permits; check COUNT semantics |
| Revise repeats same mistake | Strengthen `REVISE_USER` — `prior_sql`, full schema, explicit issue |
| Revise fixes SQL but verify still fails | Align verify rules with what revise targets (e.g. DISTINCT, LIMIT N) |
| Empty `sql` / prose instead of SQL | Tighten output format in GENERATE/REVISE; confirm `_strip_thinking` working |
| `could not parse verifier output` | Stricter `VERIFY_SYSTEM` JSON-only; check `_parse_json_object` |
| SQL error on quoted columns | Remind: double-quote identifiers (schema already quoted) |

**Tuning workflow:**

1. Change one prompt block (VERIFY or REVISE usually)
2. Restart agent (`Ctrl+C` → re-run uvicorn) — prompts are imported at startup
3. Re-run the failing question via curl or direct `graph.invoke`
4. Repeat until acceptance criteria met

**30B-specific notes:**

- First-pass SQL quality is much higher than 0.6B — you may need a **harder** question than `formula_1` to trigger revise, or temporarily test with a deliberately broken prompt to confirm loop wiring
- Verifier `max_tokens=128` in `verify_node` is sufficient for JSON — do not raise without reason (longer outputs break JSON parse)
- `llm()` default `max_tokens=256` for SQL nodes — adequate for BIRD queries; raise only if truncated SQL seen in `history`

---

### Step 6 — Confirm `MAX_ITERATIONS` cap

Default is **3** (`MAX_ITERATIONS` env or `graph.py`). README allows 3–5.

```bash
# optional override for one test
MAX_ITERATIONS=5 uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
```

**Decision guide on H100:**

| Observation | Action |
|-------------|--------|
| Most failures fixed on first revise | Keep `3` |
| Revise often helps on iter 2 but cap stops early | Try `5` for Phase 5 eval; measure latency impact in Phase 6 |
| Revise is no-op (same SQL repeated) | Fix prompts, don't raise cap |
| Cap hit with `ok: false` frequently | Check reviser prompt; consider cap `5` only if iter-2 SQL is closer |

Document final choice in scratch log; finalize in `REPORT.md` during Phase 6/7.

---

### Step 7 — Optional: Grafana under agent load

With Phase 2 dashboard open (http://localhost:3000 → **vLLM serving**):

```bash
# fire 5 /answer requests in parallel
for db in superhero financial formula_1; do
  curl -s -X POST http://localhost:8001/answer \
    -H "Content-Type: application/json" \
    -d "{\"question\": \"test", \"db\": \"$db\"}" &
done
wait
```

Better: re-run the five real questions sequentially and watch:

- **Prefill** panels spike (large schema in every generate/verify/revise call)
- **Prefix cache** benefit if enabled in `start_vllm.sh` — same schema prefix across calls
- **Running / waiting** — 2–3 serial LLM calls per `/answer` vs parallel probe burst

Note idle vs under-agent KV usage — informs Phase 6 `max-num-seqs` tuning.

---

### Step 8 — Revisit Phase 1 vLLM config (post-agent)

After real `/answer` traffic, check whether Phase 1 flags still fit:

```bash
curl -s http://localhost:8000/metrics | grep -E 'gpu_cache|num_requests|prefix_cache'
```

| Signal | Action |
|--------|--------|
| KV cache near 100% under single-threaded `/answer` | Lower `--max-num-seqs` or `--gpu-memory-utilization` in `start_vllm.sh` |
| OOM on long-schema DBs (e.g. `california_schools`) | Confirm `--max-model-len 8192` sufficient; trim if KV-bound |
| Prefix cache hits low | Expected if schema differs per `db_id`; still helps on revise loops for same DB |

Update `REPORT.md` Phase 1 notes if you change flags — do not restart vLLM casually.

---

## Phase 3 completion checklist

### H100 / submission (this session)

- [x] 30B vLLM healthy on `:8000`; agent on `:8001`
- [x] `.env` points agent at local 30B (no Path A overrides)
- [x] `GET /health` on `:8001` returns `{"status":"ok"}`
- [x] 5 eval questions tested via `POST /answer` on 30B
- [x] At least **one** test shows `iterations >= 2` and `history` contains `"node": "revise"` (`formula_1`)
- [x] At least **one** test returns `ok: true` with non-empty `rows` (5/5 passed)
- [x] Prompts tuned for 30B (VERIFY not too lenient; REVISE not no-op) — no changes needed
- [x] Scratch log: [`phase3_h100_scratch_log.md`](phase3_h100_scratch_log.md)
- [x] `MAX_ITERATIONS` chosen: **3** (revise fixed formula_1; no cap hits)

### Already done locally (reference only)

- [x] All six prompts in `agent/prompts.py`
- [x] `verify_node`, `revise_node`, `route_after_verify` in `agent/graph.py`
- [x] Execution-error short-circuit before LLM verify
- [x] JSON + SQL parsing helpers (`_parse_json_object`, `_extract_sql`, `_strip_thinking`)
- [x] Qwen3 `enable_thinking: false` in `llm()` extra_body
- [x] Graph wiring + `agent/server.py` HTTP API
- [x] Verify→revise loop mechanics validated (stand-in model or hosted API)

---

## Troubleshooting (H100)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Connection refused` on `/answer` | Agent not running | Start uvicorn on `:8001` |
| `Connection error` in graph | vLLM down or wrong `VLLM_BASE_URL` | Confirm `:8000`; fix `.env` |
| `404` / model not found | `VLLM_MODEL` mismatch | Match `.env` to `/v1/models` id |
| `500` from `/answer` | Graph exception | Read `detail`; check LLM connectivity |
| `iterations` always `1` on 30B | Verifier too lenient or first SQL always passes | Harden VERIFY; try harder questions (formula_1, california_schools) |
| `iterations` hits cap, `ok: false` | Revise not fixing root issue | Tune REVISE_USER; check `prior_sql` in prompt |
| Empty `sql` | Thinking tags or prose-only reply | Confirm `enable_thinking: false`; check `_extract_sql` |
| JSON parse errors in verify | Model wrapped JSON in fences | `_parse_json_object` should handle — tighten VERIFY_SYSTEM |
| Good SQL, `ok: false`, verify issue about duplicates | JOIN granularity | REVISE: add DISTINCT / tighten JOINs |
| Very slow `/answer` (30s+) | 2–3 serial 30B calls + long schema | Normal for uncached cold start; time warm requests |
| OOM on agent requests | vLLM KV saturated | Lower `max-num-seqs`; fewer concurrent `/answer` |
| `FileNotFoundError` for DB | Data not loaded | `uv run python scripts/load_data.py` |

---

## What to defer (but plan for)

| Item | When |
|------|------|
| `screenshots/langfuse_trace.png` | Phase 4 — capture revise waterfall |
| Full 30-question eval + `pass_rate_by_iteration` | Phase 5 (`evals/run_eval.py`) |
| `screenshots/grafana_eval_run.png` | Phase 5 eval batch |
| Final `MAX_ITERATIONS` vs latency tradeoff | Phase 6 load test + Langfuse traces |
| Agent value paragraph in `REPORT.md` | Phase 7 |
| Prefix cache hit-rate panel | Phase 6 if tuning serving |
| Hosted API / Path A | Local dev only — not submission |

**After Phase 3:** proceed to Phase 4 Langfuse traces; reuse the same 5–10 questions, ensuring at least one trace shows `revise`.

---

## Suggested slot timeline (Phase 3)

Assumes Phase 1 vLLM already running (avoid 30B restart):

| Block | Action |
|-------|--------|
| 0–5 min | Confirm vLLM + `.env`; start agent on `:8001` |
| 5–20 min | Run 5 `/answer` tests; record scratch log |
| 20–45 min | Prompt tuning loop (VERIFY/REVISE) on failing or no-revise cases |
| 45–55 min | Re-run 5 tests; confirm revise + at least one `ok: true` |
| 55–60 min | Optional Grafana `/answer` burst; note KV / prefill |
| 60+ min | **Phase 4** — Langfuse traces, or **Phase 5** eval baseline |

Keep vLLM and agent running across phases if slot time allows.

---

## File touch map (H100 session)

| File | Action on H100 |
|------|----------------|
| `agent/prompts.py` | **Primary** — tune VERIFY/REVISE (and GENERATE if needed) |
| `agent/graph.py` | Change only if 30B exposes parsing bugs |
| `.env` | Confirm 30B model; comment Path A overrides |
| `scripts/start_vllm.sh` | Revisit only after Step 8 KV observations |
| `agent/server.py` | No changes expected |
| `_notes/` scratch log | Local vs H100 comparison table |

---

## Relationship to later phases

| Phase | Dependency on Phase 3 |
|-------|------------------------|
| **1 (vLLM)** | Revisit flags after real schema-heavy agent prompts |
| **2 (Grafana)** | `/answer` load shows prefill + prefix cache differently than probes |
| **4 (Langfuse)** | Traces need working agent; `phase4_smoke.py` reuses `/answer` |
| **5 (Evals)** | `run_eval.py` calls `POST /answer`; per-iteration scoring reads `history` |
| **6 (SLO)** | 2–3 LLM calls/request; `MAX_ITERATIONS` drives tail latency |
| **7 (Report)** | Agent value cites revise examples + per-iteration pass rates |

---

## Next phase

**Phase 4 (Agent o11y)** — Langfuse traces on the running agent:

1. Confirm `LANGFUSE_*` in `.env` (already seeded by docker-compose or manual project)
2. `uv run python scripts/phase4_smoke.py --count 10 --batch-id h100-phase4`
3. Capture `screenshots/langfuse_trace.png` (revise visible) and `screenshots/langfuse_tags.png`

See [README Phase 4](../README.md#phase-4-agent-o11y) and [`_local_dev/phase_4_plan.md`](_local_dev/phase_4_plan.md).

**Phase 5 (Evals)** — full baseline on this same agent + vLLM stack:

```bash
uv run python evals/run_eval.py --agent-url http://localhost:8001/answer --output results/eval_baseline.json
```

Compare `pass_rate_by_iteration` to your Phase 3 scratch log.
