#!/usr/bin/env bash
#
# H100 production launcher — Qwen3-30B-A3B (assignment submission model).
# Do not use on a laptop; use scripts/start_vllm_local.sh for local dev.
# Reference: https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html

set -euo pipefail

MODEL="Qwen/Qwen3-30B-A3B-Instruct-2507"
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
  --port 8000
  --dtype bfloat16
  --max-model-len 8192
  --gpu-memory-utilization 0.92
  --max-num-seqs 64
  --enable-prefix-caching
  --enable-chunked-prefill
)

if [[ -n "${HF_TOKEN:-}" ]]; then
  ARGS+=(--hf-token "$HF_TOKEN")
fi

cd "$REPO_ROOT"
exec uv run python -m vllm.entrypoints.openai.api_server "${ARGS[@]}"
