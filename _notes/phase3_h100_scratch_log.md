# Phase 3 H100 scratch log

Run date: 2026-06-19  
Model: `Qwen/Qwen3-30B-A3B-Instruct-2507`  
`MAX_ITERATIONS`: 3 (default — kept; revise fixed formula_1 on iter 1)

## Local vs H100 (5 probe questions)

| # | `db_id` | Local `iterations` | H100 `iterations` | H100 `ok` | Revise helped? | Prompt note |
|---|---------|-------------------|-------------------|-----------|----------------|-------------|
| 1 | `superhero` | (not re-run) | 1 | true | — | First-pass JOIN + COUNT correct |
| 2 | `financial` | (not re-run) | 1 | true | — | District filter correct first pass |
| 3 | `formula_1` | often 2+ locally | **2** | true | **yes** | Verifier flagged duplicate rows; revise added DISTINCT |
| 4 | `california_schools` | (not re-run) | 1 | true | — | ORDER BY + LIMIT 5 correct |
| 5 | `codebase_community` | (not re-run) | 1 | true | — | Date filter + badge name correct |

## Acceptance

- [x] 5/5 `ok: true` with non-empty rows
- [x] `formula_1`: `iterations=2`, `history` contains `"node": "revise"`
- [x] No prompt changes required on 30B (local prompts transferred cleanly)

## vLLM post-agent metrics (idle)

- `gpu_cache_usage_perc`: 0% (sequential smoke, no KV pressure)
- Prefix cache: ~67k hits / ~85k queries (~79% token reuse across generate/verify/revise)

## MAX_ITERATIONS decision

Keep **3**. One revise success on formula_1; no cap hits; raising to 5 would add latency without evidence of benefit on this smoke set.

## Next

- Phase 4: `uv run python scripts/phase4_smoke.py --count 10 --batch-id h100-phase4`
- Phase 5: full eval baseline on same agent stack
