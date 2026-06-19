#!/usr/bin/env bash
# Phase 4 screenshot helper — open Langfuse and capture submission PNGs.
#
# Prerequisite: Phase 4 smoke batch already run (see phase4_h100_scratch_log.md).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p screenshots

BATCH_ID="${1:-h100-phase4-20260619-1403}"
REVISE_TRACE_ID="${2:-6f576c3dcccd7637d16df880048e0a20}"

echo "=== Phase 4 Langfuse screenshot helper ==="
echo
echo "Login:  http://localhost:3001"
echo "        dev@langfuse.com / course-dev-password"
echo
echo "Batch:  ${BATCH_ID}"
echo "Revise trace (formula_1, iterations=2): ${REVISE_TRACE_ID}"
echo
echo "--- Screenshot 1: screenshots/langfuse_trace.png ---"
echo "  1. Tracing → open trace:"
echo "     http://localhost:3001/project/default/traces/${REVISE_TRACE_ID}"
echo "  2. Expand span tree — show generate_sql → execute → verify → revise → execute → verify"
echo "  3. Click one LLM span — prompt/response/tokens visible"
echo "  4. Save as screenshots/langfuse_trace.png"
echo
echo "--- Screenshot 2: screenshots/langfuse_tags.png ---"
echo "  1. Tracing → filter Tags: batch_id:${BATCH_ID}"
echo "     (or Metadata batch_id = ${BATCH_ID})"
echo "  2. Show columns: Name, Tags (run_type, batch_id, config_label, iterations)"
echo "  3. At least 10 traces visible from the smoke batch"
echo "  4. Save as screenshots/langfuse_tags.png"
echo
echo "Verify:"
echo "  ls -la screenshots/langfuse_trace.png screenshots/langfuse_tags.png"
