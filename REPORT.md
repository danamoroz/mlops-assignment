# Assignment Report

**Status:** Submission-ready — H100 30B numbers, all deliverables present (2026-06-19).

---

## Serving configuration

**Production model:** `Qwen/Qwen3-30B-A3B-Instruct-2507`  
**Production hardware:** 1× H100 80GB  
**Launch script:** `scripts/start_vllm.sh`

| Flag | Value | One-line justification |
|------|-------|------------------------|
| `--model` | `Qwen/Qwen3-30B-A3B-Instruct-2507` | Fixed assignment model; MoE A3B active experts keep per-token cost manageable |
| `--dtype` | `bfloat16` | Native H100 dtype; BF16 weights (~57 GiB) fit with KV headroom — no quant needed |
| `--max-model-len` | `8192` | Covers 1.5–3K schema + question with margin; longer values waste KV slots |
| `--gpu-memory-utilization` | `0.92` | Leaves ~15 GiB KV cache after 57 GiB weights; idle GPU ~75 GiB used |
| `--max-num-seqs` | `64` | Phase 6: raised from 32; KV stayed ~10% under load — waiting queue was the limit, not memory |
| `--max-num-batched-tokens` | `8192` (default) | Matches chunked prefill cap; good for mixed long-schema prefill + short SQL decode |
| `--enable-prefix-caching` | on | generate / verify / revise share the same schema prefix each request |
| `--enable-chunked-prefill` | on | Reduces TTFT spikes on long schema prefills before decode-bound phase |
| quantization | none | BF16 MoE fits 80GB; quant deferred unless Phase 6 concurrency needs more KV |

**Agent env (Phase 6 final):** `MAX_ITERATIONS=2` — caps revise loop; same 43.3% execution accuracy as baseline on eval.

Startup: 57 GiB weights loaded in 164 s; **15.2 GiB KV cache** headroom. Five probes via `scripts/probe_vllm_sql.sh` returned plausible SQL (`screenshots/vllm_manual_query.png`).

---

## Baseline evaluation

### Method

Execution-accuracy benchmark on 30 questions (`evals/eval_set.jsonl`). For each question, run the agent's final SQL and the gold SQL against the target SQLite DB, canonicalize row sets (sorted rows, string cells, `None` → `""`), and compare. Match → correct. No string matching on SQL text.

Per-iteration pass rate: for iteration *k*, score the *k*-th SQL attempt in agent history (generate at k=0, first revise at k=1, etc.). If the agent stops early, later iterations carry forward the same SQL.

### Results (H100 — 2026-06-19, self-hosted vLLM)

| Metric | Value |
|--------|-------|
| `final_pass_rate` | **43.3%** (13/30) |
| `pass_rate_by_iteration` | iter 0: **40.0%** / iter 1: **43.3%** / iter 2: **43.3%** |
| `avg_agent_iterations` | **1.67** |
| `agent_ok_rate` | **76.7%** |
| Wall clock | 45.6 s (30 questions, sequential) |

Grafana during eval: `screenshots/grafana_eval_run.png`.

### Commentary

Baseline (`MAX_ITERATIONS=3`): **43.3%** execution accuracy with a **+3.3 pp** lift from iter 0 (40%) to iter 2 (43.3%). Iter 1 and iter 2 are identical — all improvement comes from the first revise. `agent_ok_rate` **76.7%** vs **43.3%** execution accuracy — verifier accepts SQL that returns wrong row sets on many questions. Histogram: 19 one-round, 2 two-round, 9 three-round runs.

**Revise success** (`formula_1`, Australian GP coordinates): iter 0 missed `DISTINCT`; iter 1 added `SELECT DISTINCT` and matched gold rows (`screenshots/langfuse_trace.png`). **Revise failure** (`financial`, district crimes): three rounds, wrong column/join never fixed despite verifier cycles.

Only 1/30 questions flipped wrong→correct via revise — the loop is mostly a no-op for execution accuracy.

---

## SLO tuning

### Platform SLO

> P95 end-to-end agent latency **< 5 seconds**, **10+ RPS** (1 RPS = 1 full agent run per second) over a **5-minute** window.

End-to-end = wall clock from `POST /answer` to response (2–3 LLM calls, SQLite, Python overhead).

### Baseline vs SLO (H100 — 2026-06-19)

| Metric | Baseline (`max-num-seqs=32`, `MAX_ITERATIONS=3`) | SLO target | Pass? |
|--------|--------------------------------------------------|------------|-------|
| `latency_p95` | **113.6 s** | < 5 s | **No** |
| `latency_p50` | 53.8 s | — | |
| `requested_rps` | 10 | ≥ 10 | Yes |
| `achieved_rps` | 7.14 | ~10 | No |
| ok / total | 922 / 3000 (30.7%) | ~100% | No |
| `timeouts` | 1780 | 0 | No |

During baseline load, Grafana showed **`num_requests_running` pegged at 32** with **`num_requests_waiting` 3–6** while **KV cache usage ~10%** — concurrency limit, not KV memory (`screenshots/grafana_serving.png`, `screenshots/grafana_before.png`).

### Iteration log (H100)

1. saw running at 32 and waiting queue 3–6 with KV cache ~10% → hypothesized `--max-num-seqs` too low for offered load, not KV-bound → changed `max-num-seqs` 32→64 → waiting dropped to 0, ok rate 30.7%→49.9%, P95 113.6→110.9 s (marginal latency gain)
2. saw agent P95 still ~110 s with 2–3 serial LLM spans per request dominating wall clock → hypothesized capping revise reduces round-trips without large eval loss → changed `MAX_ITERATIONS` 3→2 (kept `max-num-seqs=64`) → ok 87.1% (2614/3000), timeouts 1780→7, P95 113.6→**83.4 s**, P50 53.8→33.3 s (`screenshots/grafana_after.png`)
3. saw short-window smoke at 10 RPS improve to P95 9.1 s but 300 s sustained load still >>5 s → hypothesized higher concurrency might help decode backlog → changed `max-num-seqs` 64→96 (120 s probe, `MAX_ITERATIONS=2`) → P95 44.8 s at 120 s (not clearly better than iter 2 at steady state) → **reverted to 64** for final config
4. push-past at 12 RPS × 120 s on final config → P95 115.9 s, ok 44.4%, timeouts 184 — **timeouts and HTTP 500s** spike first under overload

### Final numbers (H100)

| Metric | Best achieved (final config) |
|--------|------------------------------|
| Config | `max-num-seqs=64`, `MAX_ITERATIONS=2`, other flags unchanged |
| `latency_p95` | **83.4 s** (10 RPS × 300 s) |
| `latency_p50` | 33.3 s |
| ok rate | **87.1%** (2614 / 3000) |
| `timeouts` | 7 |
| `achieved_rps` | 7.40 |

60 s warm-up smoke on final config showed P95 **9.1 s** — misleading vs sustained 300 s run; queue depth builds over the window.

### Quality after tuning

| Metric | Baseline eval | After tuning | Δ |
|--------|---------------|--------------|---|
| `final_pass_rate` | 43.3% | **43.3%** | 0 |
| `pass_rate_by_iteration` | 40 / 43.3 / 43.3% | 40 / 43.3 / 43.3% | flat |
| `avg_agent_iterations` | 1.67 | **1.37** | −0.30 |
| `agent_ok_rate` | 76.7% | **73.3%** | −3.4 pp |

Quality survived: same headline pass rate; revise still adds +3.3 pp at iter 1 on the 30-question eval.

### Verdict (H100)

**SLO MISS.** At 10 RPS × 300 s on the best tuned config, P95 agent latency was **83.4 s** — **78.4 s above** the 5 s target. Serving tuning (`max-num-seqs` 32→64) cleared the vLLM waiting queue (KV still ~10%) and raised ok rate from 31% to 87%, but serial multi-LLM agent work (~2 calls/request at `MAX_ITERATIONS=2`) dominates end-to-end time under sustained concurrency. Hitting P95 < 5 s at 10+ agent RPS would require sub-2.5 s per full agent run, which is not achievable with 2+ dependent 30B calls per request at this load. Push-past at 12 RPS caused mass timeouts (184) and HTTP 500s before Grafana KV panels saturated.

---

## Agent value

The verify→revise loop adds a **small** amount of execution accuracy on H100 30B but is **not justified** for throughput at 10 RPS. Baseline eval (`MAX_ITERATIONS=3`): **43.3%** pass rate, iter 0 **40%** → iter 2 **43.3%** (+3.3 pp on n=30); only one question flipped wrong→correct via revise (`formula_1` DISTINCT fix). After Phase 6 tuning (`MAX_ITERATIONS=2`), pass rate stayed **43.3%** with `avg_agent_iterations` **1.37** vs **1.67** — same headline accuracy, fewer LLM round-trips. `agent_ok_rate` fell slightly (76.7% → 73.3%). Under load, capping iterations cut timeouts dramatically (1780 → 7 on 300 s run) but P95 remained **83 s** because each agent request still runs **generate → verify** serially (~2× 30B latency per user request). Failures are predominantly first-attempt SQL shape errors; verify often accepts wrong row sets. Gains require stricter verification or better generate prompts, not more revise rounds at production RPS.

---

## Next steps

Specific follow-ups tied to observed bottlenecks (not generic infra):

1. **Agent architecture for SLO** — replace serial verify LLM call with cheaper checks (row-count bounds, `EXPLAIN`) or batch generate+verify; Phase 6 showed 2× 30B calls/request cannot meet 5 s P95 at 10 RPS regardless of `max-num-seqs` tuning.
2. **Concurrency headroom confirmed** — KV cache stayed ~10% at 10 RPS; `--max-num-seqs` was the scheduler bottleneck (waiting queue at 32, cleared at 64). Further gains need agent-side parallelism, not more KV.
3. **Stricter verify prompt** — target JOIN / `DISTINCT` / filter mismatches; 73–77% `agent_ok_rate` vs 43% execution accuracy means verify is too lenient.
4. **Warm-up vs sustained load** — 60 s smoke showed P95 9 s; 300 s sustained showed 83 s; SLO testing must use full 5-minute windows.
5. **Eval expansion** — add failure-mode cases (`financial` column choice) to measure whether prompt changes help iter 0 more than extra revise rounds.
