#!/usr/bin/env bash
# Phase 6 Path A — load test + eval via Nebius (no local vLLM).
#
# Run each step in order. Keep the agent in a **separate terminal** — this
# script does NOT start/stop uvicorn (that was causing restarts mid-run).
#
# Terminal 1 — agent (restart when MAX_ITERATIONS changes):
#   cd /path/to/repo && set -a && source .env && set +a
#   export OPENAI_API_KEY="${NEBIUS_API_KEY:-$OPENAI_API_KEY}"
#   MAX_ITERATIONS=3 uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
#
# Terminal 2 — load tests / eval (this script):
#   bash scripts/run_phase6_path_a.sh load-baseline
#   # restart agent with MAX_ITERATIONS=2, then:
#   bash scripts/run_phase6_path_a.sh load-tuned
#   bash scripts/run_phase6_path_a.sh eval

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

RPS=1
DURATION=60
TIMEOUT=180
DRAIN=300
STEP="${1:-help}"

for arg in "$@"; do
  case "$arg" in
    --rps=*) RPS="${arg#*=}" ;;
    --duration=*) DURATION="${arg#*=}" ;;
    --timeout=*) TIMEOUT="${arg#*=}" ;;
  esac
done

require_agent() {
  if ! curl -sf http://localhost:8001/health >/dev/null 2>&1; then
    echo "error: agent not running on :8001" >&2
    echo "Start in another terminal:" >&2
    echo "  set -a && source .env && set +a" >&2
    echo "  export OPENAI_API_KEY=\"\${NEBIUS_API_KEY:-\$OPENAI_API_KEY}\"" >&2
    echo "  MAX_ITERATIONS=3 uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001" >&2
    exit 1
  fi
}

run_load() {
  local batch_id="$1"
  local config_label="$2"
  local out="$3"
  echo "==> load: ${RPS} RPS × ${DURATION}s → $out"
  echo "    batch_id=$batch_id  config_label=$config_label"
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

case "$STEP" in
  load-baseline)
    require_agent
    run_load "nebius-baseline-${DURATION}s" "nebius-30b-baseline" "results/load_test_baseline.json"
    ;;
  load-tuned)
    require_agent
    echo "note: agent should be running with MAX_ITERATIONS=2"
    run_load "nebius-iter-maxiter2-${DURATION}s" "nebius-30b-maxiter2" "results/load_test_iter_maxiter2.json"
    ;;
  eval)
    require_agent
    echo "==> eval → results/eval_after_tuning.json"
    uv run python evals/run_eval.py --out results/eval_after_tuning.json
    jq '.summary' results/eval_after_tuning.json
    ;;
  trace-sample)
    require_agent
    BATCH_ID="${2:-load-trace-sample-$(date +%s)}"
    CONFIG_LABEL="${3:-nebius-30b-baseline}"
    echo "note: agent must have Langfuse ON (no LANGFUSE_DISABLED=1)"
    uv run python scripts/phase6_trace_sample.py \
      --batch-id "$BATCH_ID" \
      --config-label "$CONFIG_LABEL" \
      --count 5
    ;;
  help|*)
    cat <<EOF
Phase 6 Path A — run one step at a time (agent must already be up on :8001).

  bash scripts/run_phase6_path_a.sh load-baseline   # MAX_ITERATIONS=3 agent
  bash scripts/run_phase6_path_a.sh load-tuned      # restart agent with MAX_ITERATIONS=2
  bash scripts/run_phase6_path_a.sh trace-sample [batch_id] [config_label]
  bash scripts/run_phase6_path_a.sh eval

Load tests: use LANGFUSE_DISABLED=1 on the agent to avoid export noise.
Trace sample: restart agent WITHOUT LANGFUSE_DISABLED, then run trace-sample.

Options: --rps=1 --duration=60 --timeout=180

Defaults: 1 RPS, 60s duration (~2 min wall with drain). Increase --duration for longer runs.
EOF
    ;;
esac
