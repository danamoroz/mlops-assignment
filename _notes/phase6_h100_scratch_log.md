# Phase 6 H100 scratch log

Run date: 2026-06-19  
Model: `Qwen/Qwen3-30B-A3B-Instruct-2507` (self-hosted vLLM)  
SLO: P95 agent latency < 5s, 10+ RPS, 300s window  
**Verdict: MISS** — best P95 83.4s at 10 RPS × 300s

## Final config

| Component | Value |
|-----------|-------|
| `scripts/start_vllm.sh` | `max-num-seqs=64`, `gpu-memory-utilization=0.92`, `max-model-len=8192`, prefix caching + chunked prefill |
| Agent env | `MAX_ITERATIONS=2`, `LANGFUSE_DISABLED=1` during load |

## Iteration table

| Iter | config_label | change | p95 | p50 | ok/total | timeouts | achieved_rps | notes |
|------|--------------|--------|-----|-----|----------|----------|--------------|-------|
| smoke | h100-30b-baseline | — | 5.2s | 1.3s | 104/120 | 0 | 1.88 | 2 RPS × 60s |
| baseline | h100-30b-baseline | — | **113.6s** | 53.8s | 922/3000 | 1780 | 7.14 | running=32, waiting 3–6, KV ~10% |
| iter1 | h100-30b-maxseqs-64 | max-num-seqs 32→64 | 110.9s | 51.9s | 1497/3000 | 1124 | 7.14 | waiting→0 |
| iter2 | h100-30b-maxiter2 | MAX_ITER 3→2 | **83.4s** | 33.3s | 2614/3000 | 7 | 7.40 | **best 300s run** |
| iter2 smoke | h100-30b-maxiter2 | (60s warm) | 9.1s | 3.5s | 504/600 | 0 | 5.0 | warm-up misleading |
| iter3 probe | h100-30b-maxseqs-96 | max-num-seqs 64→96 | 44.8s | 26.0s | 1040/1200 | 1 | 6.67 | 120s only; reverted to 64 |
| push | h100-30b-final | 12 RPS × 120s | 115.9s | — | 444/1200 | 184 | — | overload: timeouts first |

## Eval after tuning

| Metric | Baseline | After tuning |
|--------|----------|--------------|
| `final_pass_rate` | 43.3% | 43.3% |
| `avg_agent_iterations` | 1.67 | 1.37 |
| `agent_ok_rate` | 76.7% | 73.3% |

## Key diagnosis

- vLLM waiting queue saturated at `max-num-seqs=32` while KV cache ~10% — not memory-bound
- Raising to 64 cleared waiting queue; agent P95 still >>5s due to 2+ serial LLM calls per request
- `MAX_ITERATIONS=2` cut timeouts 1780→7 and P95 113→83s without eval regression

## Artifacts

- `results/load_test_h100_baseline.json`
- `results/load_test_h100_iter1.json`
- `results/load_test_h100_iter2.json`
- `results/load_test_h100_push_12rps.json`
- `results/eval_after_tuning.json`

## Screenshots (manual)

Save to `screenshots/` if captured during runs:
- `grafana_serving.png` — baseline 10 RPS load
- `grafana_before.png` — baseline waiting queue at cap
- `grafana_after.png` — iter1 waiting queue cleared
