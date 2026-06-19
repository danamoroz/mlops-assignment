# Phase 4 H100 scratch log

Run date: 2026-06-19  
Model: `Qwen/Qwen3-30B-A3B-Instruct-2507`  
Langfuse: `http://localhost:3001` (keys from docker-compose seed)

## Preflight

- [x] Langfuse stack up (`langfuse-web`, `langfuse-worker`)
- [x] vLLM on `:8000` — 30B model id confirmed
- [x] Agent on `:8001` — `langfuse_enabled: true`
- [x] `.env` — `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`

## Manual smoke (revise proof)

- **batch_id:** `h100-phase4-manual`
- **question:** Australian GP coordinates (`formula_1`)
- **result:** `ok: true`, `iterations: 2`, history includes `revise`
- **trace_id:** `97d7bd6ef2b99d88f6651c1b19eb4e8f`

## 10-question batch

```bash
uv run python scripts/phase4_smoke.py \
  --count 10 \
  --batch-id h100-phase4-20260619-1403 \
  --source phase4_h100
```

| Metric | Value |
|--------|-------|
| `batch_id` | `h100-phase4-20260619-1403` |
| Total | 10 |
| `ok` | 7 |
| `with_revise` | 4 |
| `config_label` | `h100-30b` (auto from `VLLM_MODEL`) |

### Per-question results

| seq | `db_id` | `ok` | `iterations` |
|-----|---------|------|--------------|
| 1 | formula_1 | true | 2 |
| 2 | superhero | true | 1 |
| 3 | california_schools | true | 1 |
| 4 | financial | false | 3 |
| 5 | financial | true | 1 |
| 6 | formula_1 | false | 3 |
| 7 | formula_1 | true | 1 |
| 8 | student_club | true | 1 |
| 9 | california_schools | true | 1 |
| 10 | toxicology | false | 3 |

## Langfuse trace verification (API)

**Best revise trace for screenshot:** `6f576c3dcccd7637d16df880048e0a20` (seq 1, formula_1)

Span waterfall confirmed:

- `attach_schema` → `generate_sql` → `execute` → `verify` → `revise` → `execute` → `verify`
- 4× `ChatOpenAI` GENERATION spans on `Qwen/Qwen3-30B-A3B-Instruct-2507`
- Token usage present (e.g. generate_sql: 1460 in / 52 out)

**Tags on batch traces:**

- `run_type:smoke`, `batch_id:h100-phase4-20260619-1403`, `config_label:h100-30b`
- Post-run: `iterations:N`, `agent_ok:true|false`

## Submission artifacts

- [x] `screenshots/langfuse_trace.png` — revise span + 30B tokens/prompt/response
- [x] `screenshots/langfuse_tags.png` — trace list with batch_id, config_label, run_type

Helper:

```bash
bash scripts/phase4_screenshot_helper.sh h100-phase4-20260619-1403 6f576c3dcccd7637d16df880048e0a20
```

Direct trace URL (via port forward `:3001`):

http://localhost:3001/project/default/traces/6f576c3dcccd7637d16df880048e0a20

## Next

- Phase 5: `uv run python evals/run_eval.py --out results/eval_baseline.json`
- Tag eval runs with `run_type=eval`, `batch_id=eval_baseline` when wiring Langfuse tags into eval harness
