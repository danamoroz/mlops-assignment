#!/usr/bin/env bash
# Print vLLM serving proof + one manual SQL probe for screenshots/vllm_manual_query.png
set -euo pipefail

echo "=== Phase 1 screenshot helper ==="
echo
echo "--- vLLM /v1/models ---"
curl -s http://localhost:8000/v1/models | jq '.data[0] | {id, max_model_len, owned_by}'
echo
echo "--- Manual SQL probe (superhero) ---"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
[[ -f "$REPO_ROOT/.env" ]] && set -a && source "$REPO_ROOT/.env" && set +a
MODEL="${VLLM_MODEL:-Qwen/Qwen3-30B-A3B-Instruct-2507}"
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    '{
      model: $model,
      messages: [
        {role: "system", content: "You are a SQLite expert. Reply with only a single SQL query, no explanation."},
        {role: "user", content: "Question: How many superheroes have the super power of \"Super Strength\"?\nDatabase: superhero"}
      ],
      temperature: 0,
      max_tokens: 256,
      chat_template_kwargs: {enable_thinking: false}
    }')" | jq -r '.choices[0].message.content'
echo
echo "Save screenshot as: screenshots/vllm_manual_query.png"
