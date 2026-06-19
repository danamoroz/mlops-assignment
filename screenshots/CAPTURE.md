# Screenshot capture checklist (H100 submission)

**Status:** All eight PNGs captured on H100 (2026-06-19). See `REPORT.md` for references.

All eight PNGs must come from **H100 + Qwen3-30B-A3B** runs ([assignment_remarks.md](../_notes/assignment_remarks.md)).

| File | When | What to show |
|------|------|--------------|
| `vllm_manual_query.png` | Phase 1 | `scripts/probe_vllm_sql.sh` or curl — 30B vLLM returning SQL |
| `grafana_serving.png` | Phase 2 / 6 load | Full `serving.json` dashboard with panels reacting under load |
| `langfuse_trace.png` | Phase 4 / 6 | Single trace waterfall: `generate_sql` → `verify` → `revise` (if fired) |
| `langfuse_tags.png` | Same session | Trace list with `run_type`, `batch_id`, `config_label` visible |
| `grafana_eval_run.png` | Phase 5 eval | Dashboard during `evals/run_eval.py` (30 questions) |
| `grafana_before.png` | Phase 6 pre-change | Panel that motivated the tuning hypothesis |
| `grafana_after.png` | Phase 6 post-change | Same panel layout after one-knob change |

**Commands:** `bash scripts/run_phase7_h100.sh help`

**Local practice:** Grafana vLLM panels stay flat on Path A (Nebius). Langfuse screenshots may be capturable locally; defer all `grafana_*.png` to H100.
