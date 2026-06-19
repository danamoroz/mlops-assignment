#!/usr/bin/env bash
#
# Phase 2 load burst — fire concurrent requests so Grafana panels react.
# Usage:
#   bash scripts/burst_vllm_load.sh              # parallel SQL probes
#   bash scripts/burst_vllm_load.sh sustained    # ~2 min steady traffic
#   bash scripts/burst_vllm_load.sh kv-pressure  # long outputs for KV cache panels

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="${1:-parallel}"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

BASE_URL="${VLLM_BASE_URL:-http://localhost:8000}"
BASE_URL="${BASE_URL%/v1}"
BASE_URL="${BASE_URL%/}"
MODEL="${VLLM_MODEL:-Qwen/Qwen3-0.6B}"

parallel_burst() {
  echo "Firing 20 SQL probes (4 concurrent) against $BASE_URL ..."
  seq 1 20 | xargs -P4 -I{} bash -c "bash '$SCRIPT_DIR/probe_vllm_sql.sh' '$BASE_URL' >/dev/null 2>&1 || true"
  echo "Done."
}

sustained_burst() {
  echo "Sustained load for ~120s against $BASE_URL ..."
  local end=$((SECONDS + 120))
  while [[ $SECONDS -lt $end ]]; do
    bash "$SCRIPT_DIR/probe_vllm_sql.sh" "$BASE_URL" >/dev/null 2>&1 &
    sleep 0.5
  done
  wait
  echo "Done."
}

kv_pressure() {
  echo "KV cache pressure: 8 parallel long-generation requests ..."
  for i in $(seq 1 8); do
    curl -sf "$BASE_URL/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg model "$MODEL" \
        --argjson i "$i" \
        '{
          model: $model,
          messages: [{role: "user", content: ("Explain step by step how to write a complex SQL query with joins, subqueries, and window functions. Request " + ($i|tostring))}],
          max_tokens: 512,
          temperature: 0
        }')" >/dev/null 2>&1 &
  done
  wait
  echo "Done."
}

case "$MODE" in
  parallel) parallel_burst ;;
  sustained) sustained_burst ;;
  kv-pressure) kv_pressure ;;
  all)
    parallel_burst
    kv_pressure
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: $0 [parallel|sustained|kv-pressure|all]" >&2
    exit 1
    ;;
esac
