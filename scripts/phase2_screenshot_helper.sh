#!/usr/bin/env bash
# Phase 2 screenshot helper — run burst load while capturing Grafana dashboard.
#
# Manual step: open http://localhost:3000 (admin/admin) → Dashboards → vLLM serving
# Set time range "Last 15 minutes", refresh 5s, then save screenshot during the burst below.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p screenshots

echo "=== Phase 2 screenshot helper ==="
echo
echo "Before continuing:"
echo "  1. Open Grafana (NOT Langfuse): http://localhost:3000"
echo "     Login: admin / admin"
echo "  2. Direct link: http://localhost:3000/d/vllm-serving/vllm-serving"
echo "     Or: menu ☰ → Dashboards → Browse → vLLM serving"
echo "  3. Time range: Last 15 minutes | Refresh: 5s"
echo "  4. Zoom browser so all 3 rows (Latency, Throughput, KV cache) are visible"
echo
echo "  If the list is empty, confirm port 3000 is forwarded from the H100 VM (not 3001)."
echo

if [[ "${1:-}" != "--no-wait" ]]; then
  read -r -p "Press Enter when Grafana is open and ready to capture... " _
else
  echo "(Skipping wait — burst starts in 5s; open Grafana now if not already.)"
  sleep 5
fi

echo
echo "Starting burst load (~2 min). Capture screenshots/grafana_serving.png NOW."
echo

bash "$SCRIPT_DIR/burst_vllm_load.sh" all

echo
echo "Running sustained traffic for percentile panels..."
bash "$SCRIPT_DIR/burst_vllm_load.sh" sustained

echo
echo "Burst complete. Save screenshot as: screenshots/grafana_serving.png"
echo "Verify panels show activity spikes (especially Token throughput, Request concurrency, TTFT)."
echo "Then run: bash scripts/phase2_verify.sh"
