#!/usr/bin/env bash
# Phase 4 Path A — hosted LLM API + Langfuse (no local vLLM).
#
# Prereq: NEBIUS_API_KEY or OPENAI_API_KEY in .env (Path A block).
#
# Usage:
#   bash scripts/run_phase4_path_a.sh
#   bash scripts/run_phase4_path_a.sh --batch-id my-run
#   bash scripts/run_phase4_path_a.sh --agent-only   # keep agent running (no smoke)

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

AGENT_ONLY=false
BATCH_ID="phase4-local-test"
for arg in "$@"; do
  case "$arg" in
    --agent-only) AGENT_ONLY=true ;;
    --batch-id=*) BATCH_ID="${arg#*=}" ;;
  esac
done

if [[ -z "${NEBIUS_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" ]]; then
  echo "error: set NEBIUS_API_KEY or OPENAI_API_KEY in .env (Path A block)" >&2
  exit 1
fi

if [[ -n "${NEBIUS_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" ]]; then
  export OPENAI_API_KEY="$NEBIUS_API_KEY"
fi

echo "==> Langfuse stack"
docker compose up -d

echo "==> Waiting for Langfuse UI..."
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3001 || true)
  if [[ "$code" == "200" || "$code" == "307" ]]; then
    break
  fi
  sleep 2
done
echo "    http://localhost:3001  (dev@langfuse.com / course-dev-password)"

if [[ "$AGENT_ONLY" == true ]]; then
  echo "==> Starting agent (Ctrl+C to stop)"
  exec uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001
fi

echo "==> Starting agent (background)"
uv run uvicorn agent.server:app --host 0.0.0.0 --port 8001 &
AGENT_PID=$!
cleanup() { kill "$AGENT_PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> Waiting for agent health..."
for _ in $(seq 1 30); do
  if curl -sf http://localhost:8001/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -s http://localhost:8001/health | jq . || curl -s http://localhost:8001/health

echo "==> Smoke batch (batch_id=$BATCH_ID)"
uv run python scripts/phase4_smoke.py --batch-id "$BATCH_ID"

echo ""
echo "Done. Open Langfuse → Tracing → filter batch_id:$BATCH_ID"
