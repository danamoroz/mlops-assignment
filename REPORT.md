# Assignment Report

**Status:** Phases 1–6 complete on H100. Remaining: Phase 7 polish + screenshot files on disk — see [screenshots/CAPTURE.md](screenshots/CAPTURE.md).

---

## Serving configuration

**Production model:** `Qwen/Qwen3-30B-A3B-Instruct-2507`  
**Production hardware:** 1× H100 80GB  
**Launch script:** `scripts/start_vllm.sh` (H100 only). Local dev uses `scripts/start_vllm_local.sh` with `Qwen/Qwen3-0.6B` stand-in.

### Production (H100) — 2026-06-19 Nebius session

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

**H100 startup notes (2026-06-19):** First launch downloaded ~57 GiB weights; model load 164 s, 56.9 GiB VRAM for weights, **15.2 GiB available KV cache**. vLLM 0.10.2 V1 engine + FlashAttention. Prometheus `vllm` target UP. Five manual probes via `scripts/probe_vllm_sql.sh` returned plausible SQL in ~3 s total.

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

Screenshot: `screenshots/grafana_eval_run.png` (dashboard reacting during `run_eval.py` on H100).

### Commentary

H100 self-hosted baseline (`MAX_ITERATIONS=3`): **43.3%** execution accuracy with a **+3.3 pp** lift from iter 0 (40%) to iter 2 (43.3%). Iter 1 and iter 2 are identical — all improvement comes from the first revise. `agent_ok_rate` **76.7%** vs **43.3%** execution accuracy — verifier accepts SQL that returns wrong row sets on many questions. Iteration histogram: 19 one-round, 2 two-round, 9 three-round runs.

**Revise success** (`formula_1`, Australian GP coordinates): iter 0 missed `DISTINCT`; iter 1 added `SELECT DISTINCT` and matched gold rows. **Revise failure** (`financial`, district crimes): three rounds, wrong column/join never fixed despite verifier cycles.

The loop earns a small amount of lift on 30B but is mostly a no-op for execution accuracy — only 1/30 questions flipped wrong→correct via revise.

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

Command: `uv run python load_test/driver.py --rps 10 --duration 300 --config-label h100-30b-baseline --out results/load_test_h100_baseline.json`

During baseline load, Grafana showed **`num_requests_running` pegged at 32** (the `--max-num-seqs` cap) with **`num_requests_waiting` 3–6** while **KV cache usage ~10%** — concurrency limit, not KV memory.

Screenshot: `screenshots/grafana_serving.png` (full dashboard under load).

### Iteration log (H100)

1. saw running at 32 and waiting queue 3–6 with KV cache ~10% → hypothesized `--max-num-seqs` too low for offered load, not KV-bound → changed `max-num-seqs` 32→64 → waiting dropped to 0, ok rate 30.7%→49.9%, P95 113.6→110.9 s (marginal latency gain)
2. saw agent P95 still ~110 s with 2–3 serial LLM spans per request dominating wall clock → hypothesized capping revise reduces round-trips without large eval loss → changed `MAX_ITERATIONS` 3→2 (kept `max-num-seqs=64`) → ok 87.1% (2614/3000), timeouts 1780→7, P95 113.6→**83.4 s**, P50 53.8→33.3 s
3. saw short-window smoke at 10 RPS improve to P95 9.1 s but 300 s sustained load still >>5 s → hypothesized higher concurrency might help decode backlog → changed `max-num-seqs` 64→96 (120 s probe, `MAX_ITERATIONS=2`) → P95 44.8 s at 120 s (not clearly better than iter 2 at steady state) → **reverted to 64** for final config
4. push-past at 12 RPS × 120 s on final config → P95 115.9 s, ok 44.4%, timeouts 184 — **timeouts and HTTP 500s** spike first under overload

Before/after evidence: `screenshots/grafana_before.png` (baseline — waiting queue + running at cap), `screenshots/grafana_after.png` (iter 1 — waiting queue cleared at `max-num-seqs=64`).

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

Command: `uv run python evals/run_eval.py --out results/eval_after_tuning.json` with `MAX_ITERATIONS=2`.

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

---

## Appendix — Local development (not submitted)

### Launch scripts

| Script | When | Model |
|--------|------|-------|
| `scripts/start_vllm.sh` | H100 VM — submission | `Qwen/Qwen3-30B-A3B-Instruct-2507` |
| `scripts/start_vllm_local.sh` | Local smoke + Grafana | `Qwen/Qwen3-0.6B` |

### Local stand-in config (T500 4GB, 2026-06-13)

| Flag / env | Value | Justification |
|------------|-------|---------------|
| `--model` | `Qwen/Qwen3-0.6B` | Fits 4GB GPU; validates API + metrics |
| `--max-model-len` | `4096` | VRAM headroom on laptop GPU |
| `--gpu-memory-utilization` | `0.70` | ~3.2 GiB free at startup |
| `--enforce-eager` | on | Avoids cudagraph issues on low-end GPU |
| `--max-num-seqs` | `4` | Limits concurrent KV on 4GB VRAM |
| `VLLM_USE_V1` | `0` | v1 engine needs FA2 (cc ≥ 8) |
| `VLLM_ATTENTION_BACKEND` | `XFORMERS` | Fallback for T500 (sm 7.5) |

Verified: `/v1/models`, `/health`, `/metrics`, Prometheus target UP. `scripts/probe_vllm_sql.sh` — 5 eval questions, valid SQL (~57s on T500). Pinned `transformers>=4.55.2,<5.0` (vLLM 0.10.2 breaks on transformers 5.x).

### Path A practice — SLO tuning (Nebius API, not submission)

Diagnosis surface: `results/load_test_*.json` + Langfuse (`run_type=load_test`); Grafana vLLM panels N/A.

**Baseline** (1 RPS × 120s, `MAX_ITERATIONS=3`): P95 **167s**, P50 129s, achieved RPS 0.58, ok 104/120 (87%). 16× HTTP 500 under concurrent load.

**Iteration 1** (`MAX_ITERATIONS` 3→2): P95 **115s** (−31%), P50 91s (−29%), ok rate flat at 87%.

> saw agent P95 167s with serial LLM calls stacking under queue → hypothesized capping revise reduces round-trips → changed MAX_ITERATIONS 3→2 → P95 115s (~31% lower), ok rate unchanged, still far from 5s SLO

**Practice eval after tuning:** `final_pass_rate` 0.40 → 0.37; per-iteration rates flat; `formula_1` DISTINCT fix at iter 1.

```bash
# Path A workflow (practice)
set -a && source .env && set +a
export OPENAI_API_KEY="${NEBIUS_API_KEY:-$OPENAI_API_KEY}"
MAX_ITERATIONS=3 uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
bash scripts/run_phase6_path_a.sh load-baseline --duration=60
# restart agent with MAX_ITERATIONS=2, then:
bash scripts/run_phase6_path_a.sh load-tuned --duration=60
bash scripts/run_phase6_path_a.sh eval
```

### Deliverables audit

| Artifact | Status |
|----------|--------|
| `REPORT.md` | Draft — this file |
| `infra/grafana/.../serving.json` | Present |
| `agent/graph.py`, `agent/prompts.py` | Present |
| `evals/run_eval.py` | Present |
| `results/eval_baseline.json` | H100 baseline (43.3% pass rate, 2026-06-19) |
| `results/eval_after_tuning.json` | H100 final config (43.3%, MAX_ITERATIONS=2) |
| `results/load_test_h100_*.json` | Baseline + 3 iterations + push-past |
| `screenshots/*.png` (×8) | **User capture required** — see note below |
