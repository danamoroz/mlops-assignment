#!/usr/bin/env bash
#
# Phase 1 manual text-to-SQL probes against a running vLLM server.
# Usage: bash scripts/probe_vllm_sql.sh [base_url]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_URL="${1:-http://localhost:8000}"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

MODEL="${VLLM_MODEL:-Qwen/Qwen3-0.6B}"

probe() {
  local db_id="$1"
  local question="$2"
  echo "=== db: $db_id ==="
  echo "Q: $question"
  local response
  response="$(curl -sf "$BASE_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg model "$MODEL" \
      --arg q "$question" \
      --arg db "$db_id" \
      '{
        model: $model,
        messages: [
          {role: "system", content: "You are a SQLite expert. Reply with only a single SQL query, no explanation."},
          {role: "user", content: ("Question: " + $q + "\nDatabase: " + $db)}
        ],
        temperature: 0,
        max_tokens: 256,
        chat_template_kwargs: {enable_thinking: false}
      }')")"
  echo "$response" | jq -r '.choices[0].message.content // .error.message // .'
  echo
}

echo "Model: $MODEL"
echo "Base URL: $BASE_URL"
echo

probe "superhero" 'How many superheroes have the super power of "Super Strength"?'
probe "financial" "How many male clients in 'Hl.m. Praha' district?"
probe "formula_1" "What is the coordinates location of the circuits for Australian grand prix?"
probe "california_schools" "List the top five schools, by descending order, from the highest to the lowest, the most number of Enrollment (Ages 5-17). Please give their NCES school identification number."
probe "codebase_community" "How many users received commentator badges in 2014?"
