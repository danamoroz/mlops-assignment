# Assignment Report

**Status:** Phases 1–5 complete on H100 (baseline eval + Grafana screenshot). Remaining: Phase 6 SLO load test + tuning numbers — see [screenshots/CAPTURE.md](screenshots/CAPTURE.md).

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
| `--max-num-seqs` | `32` | Starting concurrency for agent's 2–3 calls/request; raise in Phase 6 toward 10+ RPS |
| `--max-num-batched-tokens` | `8192` (default) | Matches chunked prefill cap; good for mixed long-schema prefill + short SQL decode |
| `--enable-prefix-caching` | on | generate / verify / revise share the same schema prefix each request |
| `--enable-chunked-prefill` | on | Reduces TTFT spikes on long schema prefills before decode-bound phase |
| quantization | none | BF16 MoE fits 80GB; quant deferred unless Phase 6 concurrency needs more KV |

**H100 startup notes (2026-06-19):** First launch downloaded ~57 GiB weights; model load 164 s, 56.9 GiB VRAM for weights, **15.2 GiB available KV cache**. vLLM 0.10.2 V1 engine + FlashAttention. Prometheus `vllm` target UP. Five manual probes via `scripts/probe_vllm_sql.sh` returned plausible SQL in ~3 s total.

Tuning order for Phase 6: `max-num-seqs` → KV headroom → `max-model-len` → prefix caching → agent `MAX_ITERATIONS` (measure eval impact).

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

### Baseline vs SLO (H100 — replace before submission)

| Metric | Baseline | SLO target | Pass? |
|--------|----------|------------|-------|
| `latency_p95` | *(fill on H100)* | < 5s | |
| `latency_p50` | *(fill on H100)* | — | |
| `achieved_rps` | *(fill on H100)* | ≥ 10 | |
| ok / total | *(fill on H100)* | ~100% | |
| Run | `--rps 10 --duration 300` | | |

Command: `uv run python load_test/driver.py --rps 10 --duration 300 --config-label h100-30b-baseline --out results/load_test_h100_baseline.json`

Screenshot: `screenshots/grafana_serving.png` (full dashboard under load).

### Iteration log (H100 — add 3–4 lines on VM)

1. *(fill on H100)* saw … → hypothesized … → changed … → result …
2. *(fill on H100)* …
3. *(fill on H100)* …

Before/after evidence: `screenshots/grafana_before.png`, `screenshots/grafana_after.png` — same panels around the iteration that moved the targeted metric (queue depth, TTFT, or KV cache).

### Final numbers (H100)

| Metric | Best achieved |
|--------|---------------|
| `latency_p95` | *(fill on H100)* |
| `achieved_rps` | *(fill on H100)* |
| ok rate | *(fill on H100)* |

### Quality after tuning

| Metric | Baseline eval | After tuning | Δ |
|--------|---------------|--------------|---|
| `final_pass_rate` | *(H100 baseline)* | *(H100 after tuning)* | |
| `pass_rate_by_iteration` | *(H100)* | *(H100)* | |
| `avg_agent_iterations` | *(H100)* | *(H100)* | |
| `agent_ok_rate` | *(H100)* | *(H100)* | |

Command: `uv run python evals/run_eval.py --out results/eval_after_tuning.json` on final H100 config.

### Verdict (H100)

*(SLO HIT / MISS — quantify gap, e.g. "P95 6.2s at 10 RPS, miss by 1.2s; waiting queue saturated before KV limit.")*

---

## Agent value

The verify→revise loop **did not** improve aggregate execution accuracy on the practice eval set. Overall pass rate was **40%** with per-iteration rates **iter 0: 40%, iter 1: 40%, iter 2: 40%** — flat, so stopping after iter 0 would have been equivalent for headline accuracy. Average agent iterations was **1.57** (histogram: 20×1-round, 3×2-round, 7×3-round). The loop's value is **not justified** for throughput given the serial LLM cost: Phase 6 practice showed capping `MAX_ITERATIONS` cut P95 ~31% while pass rate fell only 3 pp. Failures are predominantly first-attempt SQL shape errors (JOINs, `DISTINCT`, column choice); the one clear revise win (`formula_1` DISTINCT fix) shows the mechanism works when verify rejects, but verify often passes wrong SQL (`agent_ok_rate` 77% vs 40% accuracy). Gains require stricter verification or better generate prompts, not more revise rounds alone.

*(Replace percentages with H100 self-hosted eval after VM session.)*

---

## Next steps

Specific follow-ups tied to observed bottlenecks (not generic infra):

1. **Prefix caching on H100** — enable `--enable-prefix-caching` because generate, verify, and revise share the same ~1.5–3K schema block; Langfuse traces show repeated prefix tokens per agent request.
2. **Concurrency tuning** — raise `--max-num-seqs` incrementally and watch `vllm_num_requests_waiting` vs GPU KV cache usage on the serving dashboard; agent workload is 2–3 dependent calls per user request at 10 RPS.
3. **Stricter verify prompt** — target JOIN / `DISTINCT` / filter mismatches seen in eval (`formula_1` fix proves revise helps only when verify rejects; 77% `agent_ok_rate` with 40% accuracy means verify is too lenient).
4. **Eval expansion for failure modes** — add cases for column-selection errors (`financial` A14 vs A15) to measure whether prompt changes help iter 0 more than extra revise rounds.
5. **Latency-aware verify** — explore cheaper checks (e.g. `EXPLAIN`, row-count bounds) before a full second LLM call; Path A practice showed serial API round-trips dominate P95 under load.

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
| `results/eval_after_tuning.json` | Pending Phase 6 |
| `screenshots/*.png` (×8) | 4/8 present — Phase 6 panels + `vllm_manual_query.png` remaining |
