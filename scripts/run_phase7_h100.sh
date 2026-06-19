#!/usr/bin/env bash
# Phase 7 H100 finalization — submission artifact generation.
#
# Run on the H100 VM with vLLM + agent already configured for 30B.
# Screenshots are manual — this script runs the measurable steps in order.
#
# Terminal 1 — stack:
#   docker compose up -d
#   bash scripts/start_vllm.sh
#   set -a && source .env && set +a
#   export VLLM_MODEL=Qwen/Qwen3-30B-A3B-Instruct-2507
#   uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
#
# Terminal 2 — one step at a time:
#   bash scripts/run_phase7_h100.sh preflight
#   bash scripts/run_phase7_h100.sh eval-baseline    # capture screenshots/grafana_eval_run.png
#   bash scripts/run_phase7_h100.sh load-baseline  # capture screenshots/grafana_serving.png
#   bash scripts/run_phase7_h100.sh load-tuned ...   # after tuning; capture grafana_before/after
#   bash scripts/run_phase7_h100.sh eval-final
#   bash scripts/run_phase7_h100.sh summary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

RPS=10
DURATION=300
TIMEOUT=120
DRAIN=600
STEP="${1:-help}"

for arg in "$@"; do
  case "$arg" in
    --rps=*) RPS="${arg#*=}" ;;
    --duration=*) DURATION="${arg#*=}" ;;
    --batch-id=*) BATCH_ID_OVERRIDE="${arg#*=}" ;;
    --config-label=*) CONFIG_LABEL_OVERRIDE="${arg#*=}" ;;
    --out=*) OUT_OVERRIDE="${arg#*=}" ;;
  esac
done

require_vllm() {
  if ! curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    echo "error: vLLM not running on :8000 — start scripts/start_vllm.sh" >&2
    exit 1
  fi
}

require_agent() {
  if ! curl -sf http://localhost:8001/health >/dev/null 2>&1; then
    echo "error: agent not running on :8001" >&2
    exit 1
  fi
}

run_load() {
  local batch_id="$1"
  local config_label="$2"
  local out="$3"
  echo "==> load: ${RPS} RPS × ${DURATION}s → $out"
  echo "    batch_id=$batch_id  config_label=$config_label"
  echo "    capture Grafana now if this is a screenshot step"
  uv run python load_test/driver.py \
    --rps "$RPS" \
    --duration "$DURATION" \
    --timeout "$TIMEOUT" \
    --drain-timeout "$DRAIN" \
    --batch-id "$batch_id" \
    --config-label "$config_label" \
    --out "$out"
  jq '.summary' "$out"
}

print_summary() {
  echo "==> artifact summary"
  for f in \
    results/eval_baseline.json \
    results/eval_after_tuning.json \
    results/load_test_h100_baseline.json \
    screenshots/vllm_manual_query.png \
    screenshots/grafana_serving.png \
    screenshots/langfuse_trace.png \
    screenshots/langfuse_tags.png \
    screenshots/grafana_eval_run.png \
    screenshots/grafana_before.png \
    screenshots/grafana_after.png
  do
    if [[ -f "$f" ]]; then
      echo "  OK  $f"
    else
      echo "  --  $f (missing)"
    fi
  done
  echo ""
  echo "Update REPORT.md H100 placeholders, then: wc -w REPORT.md  (target ≤1800)"
}

case "$STEP" in
  preflight)
    require_vllm
    require_agent
    curl -s http://localhost:8000/v1/models | jq -r '.data[0].id'
    curl -s http://localhost:8001/health | jq .
    echo "Grafana: http://localhost:3000  Langfuse: http://localhost:3001"
    mkdir -p screenshots results
    ;;
  probe)
    require_vllm
    echo "==> manual SQL probe — capture screenshots/vllm_manual_query.png"
    bash scripts/probe_vllm_sql.sh
    ;;
  eval-baseline)
    require_agent
    echo "==> baseline eval — capture screenshots/grafana_eval_run.png during run"
    uv run python evals/run_eval.py --out results/eval_baseline.json
    jq '.summary' results/eval_baseline.json
    ;;
  load-baseline)
    require_vllm
    require_agent
    local_out="${OUT_OVERRIDE:-results/load_test_h100_baseline.json}"
    batch="${BATCH_ID_OVERRIDE:-h100-baseline-${DURATION}s}"
    label="${CONFIG_LABEL_OVERRIDE:-h100-30b-baseline}"
    echo "==> capture screenshots/grafana_serving.png while load runs"
    run_load "$batch" "$label" "$local_out"
    ;;
  load)
    require_vllm
    require_agent
    batch="${BATCH_ID_OVERRIDE:?set --batch-id=...}"
    label="${CONFIG_LABEL_OVERRIDE:?set --config-label=...}"
    out="${OUT_OVERRIDE:?set --out=...}"
    run_load "$batch" "$label" "$out"
    ;;
  eval-final)
    require_agent
    echo "==> post-tuning eval → results/eval_after_tuning.json"
    uv run python evals/run_eval.py --out results/eval_after_tuning.json
    jq '.summary' results/eval_after_tuning.json
    ;;
  trace-sample)
    require_agent
    BATCH_ID="${2:-h100-trace-$(date +%s)}"
    CONFIG_LABEL="${3:-h100-30b-baseline}"
    echo "==> capture screenshots/langfuse_trace.png + langfuse_tags.png after run"
    uv run python scripts/phase6_trace_sample.py \
      --batch-id "$BATCH_ID" \
      --config-label "$CONFIG_LABEL" \
      --count 5
    ;;
  summary)
    print_summary
    ;;
  help|*)
    cat <<EOF
Phase 7 H100 finalization — run one step at a time.

  bash scripts/run_phase7_h100.sh preflight
  bash scripts/run_phase7_h100.sh probe              # → screenshots/vllm_manual_query.png
  bash scripts/run_phase7_h100.sh eval-baseline      # → results/eval_baseline.json + grafana_eval_run.png
  bash scripts/run_phase7_h100.sh load-baseline      # → load_test_h100_baseline.json + grafana_serving.png
  bash scripts/run_phase7_h100.sh load \\
      --batch-id=h100-iter2 --config-label=h100-tuned --out=results/load_test_iter2.json
  bash scripts/run_phase7_h100.sh eval-final         # → results/eval_after_tuning.json
  bash scripts/run_phase7_h100.sh trace-sample [batch_id] [config_label]
  bash scripts/run_phase7_h100.sh summary

Options: --rps=10 --duration=300

After runs: paste H100 numbers into REPORT.md, remove practice-only text, verify screenshots/.
EOF
    ;;
esac
