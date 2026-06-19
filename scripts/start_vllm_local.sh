#!/usr/bin/env bash
#
# Local smoke-test launcher — small stand-in model for Phase 1–2 dev.
# Use scripts/start_vllm.sh on the H100 VM for the real 30B config.
#
# Reference: https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html

set -euo pipefail

MODEL="Qwen/Qwen3-0.6B"
PORT=8000

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

ARGS=(
  --model "$MODEL"
  --host 0.0.0.0
  --port "$PORT"
  --max-model-len 4096
  --gpu-memory-utilization 0.70
  --enforce-eager
  --max-num-seqs 4
)

# T500 / older GPUs: no FA2 (compute capability < 8). Prefer v0 engine + xformers.
export VLLM_USE_V1="${VLLM_USE_V1:-0}"
export VLLM_ATTENTION_BACKEND="${VLLM_ATTENTION_BACKEND:-XFORMERS}"

if [[ -n "${HF_TOKEN:-}" ]]; then
  ARGS+=(--hf-token "$HF_TOKEN")
fi

cd "$REPO_ROOT"
exec uv run python -m vllm.entrypoints.openai.api_server "${ARGS[@]}"
