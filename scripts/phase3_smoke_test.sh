#!/usr/bin/env bash
# Phase 3 H100 smoke — 5 eval questions via POST /answer
set -euo pipefail

AGENT_URL="${AGENT_URL:-http://localhost:8001/answer}"

run_test() {
  local num="$1"
  local db="$2"
  local question="$3"
  echo "=== Test $num: $db ==="
  curl -s -X POST "$AGENT_URL" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg q "$question" --arg db "$db" '{question: $q, db: $db}')" \
    | jq '{ok, iterations, sql, error, has_revise: ([.history[] | select(.node=="revise")] | length > 0), history}'
  echo
}

run_test 1 superhero 'How many superheroes have the super power of "Super Strength"?'
run_test 2 financial "How many male clients in 'Hl.m. Praha' district?"
run_test 3 formula_1 "What is the coordinates location of the circuits for Australian grand prix?"
run_test 4 california_schools "List the top five schools, by descending order, from the highest to the lowest, the most number of Enrollment (Ages 5-17). Please give their NCES school identification number."
run_test 5 codebase_community "How many users received commentator badges in 2014?"
