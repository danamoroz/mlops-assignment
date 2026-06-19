#!/usr/bin/env bash
# Phase 0 setup for Nebius H100 VM — see _notes/final_phase_0.md
#
# Prerequisite (manual): Cursor Remote-SSH to VM + forward ports 3000,9090,3001,8000,8001
#
# Usage:
#   bash scripts/setup_phase0_h100.sh           # full setup
#   bash scripts/setup_phase0_h100.sh verify    # checks only (after setup)
#   bash scripts/setup_phase0_h100.sh preflight # prerequisites only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

STEP="${1:-all}"

log() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }
fail() { echo "error: $*" >&2; exit 1; }

check_prerequisites() {
  log "preflight checks"

  command -v git >/dev/null || fail "git not found"
  command -v docker >/dev/null || fail "docker not found"
  docker compose version >/dev/null 2>&1 || fail "docker compose not found"
  command -v uv >/dev/null || fail "uv not found — curl -LsSf https://astral.sh/uv/install.sh | sh"

  py_ver="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  if python3 -c 'import sys; exit(0 if sys.version_info >= (3, 11) else 1)'; then
    log "python $py_ver OK"
  else
    fail "python 3.11+ required (found $py_ver)"
  fi

  if dpkg -l python3-dev >/dev/null 2>&1; then
    log "python3-dev installed"
  elif rpm -q python3-devel >/dev/null 2>&1; then
    log "python3-devel installed"
  else
    warn "python3-dev not detected — install before Phase 1 (vLLM torch.compile)"
  fi

  if nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | while read -r line; do
      log "GPU: $line"
    done
  else
    warn "nvidia-smi failed — expected on H100 VM; Phase 0 o11y stack still works"
  fi

  df -h . | tail -1 | awk '{print "disk: "$4" free on "$1}'
}

ensure_env() {
  if [[ ! -f .env ]]; then
    log "creating .env from .env.example"
    cp .env.example .env
    warn "Set HF_TOKEN in .env before Phase 1 — edit now if you have it"
  fi

  # shellcheck disable=SC1091
  set -a && source .env && set +a

  if [[ -n "${VLLM_BASE_URL:-}" ]] || [[ -n "${NEBIUS_API_KEY:-}" ]] || [[ -n "${OPENAI_API_KEY:-}" ]]; then
    warn "Path A / hosted API vars are set in .env — disable for H100 self-hosted vLLM"
    warn "Comment out VLLM_BASE_URL, NEBIUS_API_KEY, OPENAI_API_KEY; keep VLLM_MODEL only"
  fi

  if [[ -z "${VLLM_MODEL:-}" ]]; then
    fail "VLLM_MODEL missing in .env"
  fi

  if [[ -z "${HF_TOKEN:-}" ]]; then
    warn "HF_TOKEN empty — OK for Phase 0; required before Phase 1 model download"
  else
    log "HF_TOKEN set"
  fi

  log "VLLM_MODEL=$VLLM_MODEL"
}

install_deps() {
  log "uv sync"
  uv sync
  uv run python -c "import vllm, langgraph, langfuse; print('imports ok')"
}

load_bird() {
  local sqlite_count
  sqlite_count="$(find data/bird -maxdepth 1 -name '*.sqlite' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$sqlite_count" -ge 11 ]] && [[ -f evals/eval_set.jsonl ]] && [[ -f load_test/perf_pool.jsonl ]]; then
    log "BIRD data present ($sqlite_count sqlite files) — skipping load_data.py"
    return
  fi
  log "loading BIRD dataset (~500 MB download)"
  uv run python scripts/load_data.py
  sqlite_count="$(find data/bird -maxdepth 1 -name '*.sqlite' | wc -l | tr -d ' ')"
  [[ "$sqlite_count" -ge 11 ]] || fail "expected 11 sqlite files, got $sqlite_count"
  wc -l evals/eval_set.jsonl load_test/perf_pool.jsonl
}

start_o11y() {
  log "docker compose up -d"
  docker compose up -d

  log "waiting for core services (up to 120s)"
  local i
  for i in $(seq 1 24); do
    if curl -sf http://localhost:9090/-/ready >/dev/null 2>&1 \
      && curl -sf http://localhost:3000/api/health >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done

  docker compose ps
}

verify_uis() {
  log "service health (on VM localhost)"

  curl -sf http://localhost:9090/-/ready >/dev/null \
    && log "Prometheus :9090 OK" \
    || warn "Prometheus not ready at :9090"

  curl -sf http://localhost:3000/api/health >/dev/null \
    && log "Grafana :3000 OK" \
    || warn "Grafana not ready at :3000"

  if curl -sf http://localhost:3001/api/public/health >/dev/null 2>&1 \
    || curl -sf http://localhost:3001 >/dev/null 2>&1; then
    log "Langfuse :3001 OK"
  else
    warn "Langfuse not ready yet — try: docker compose logs -f langfuse-web"
  fi

  if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    warn "vLLM already running on :8000 (Phase 1 started early?)"
  else
    log "vLLM :8000 not running (expected for Phase 0)"
  fi

  log "Prometheus targets:"
  if curl -sf http://localhost:9090/api/v1/targets >/dev/null 2>&1; then
    curl -s http://localhost:9090/api/v1/targets \
      | uv run python -c "
import json, sys
d = json.load(sys.stdin)
for t in d.get('data', {}).get('activeTargets', []):
    job = t.get('labels', {}).get('job', '?')
    health = t.get('health', '?')
    print(f'  {job}: {health}')
"
  fi

  cat <<EOF

Phase 0 automated steps complete.

Manual checks from your LAPTOP browser (requires port forwards):
  http://localhost:9090        Prometheus → Targets → vllm should be DOWN
  http://localhost:3000        Grafana (admin / admin)
  http://localhost:3001        Langfuse → sign up (new VM instance)

Next: Phase 1 — bash scripts/start_vllm.sh
EOF
}

case "$STEP" in
  preflight) check_prerequisites ;;
  env) ensure_env ;;
  deps) install_deps ;;
  data) load_bird ;;
  o11y) start_o11y ;;
  verify) verify_uis ;;
  all)
    check_prerequisites
    ensure_env
    install_deps
    load_bird
    start_o11y
    verify_uis
    ;;
  help|*)
    cat <<EOF
Phase 0 H100 setup — _notes/final_phase_0.md

  bash scripts/setup_phase0_h100.sh            # full run
  bash scripts/setup_phase0_h100.sh preflight  # GPU, docker, uv, python
  bash scripts/setup_phase0_h100.sh verify     # UI health after setup

Before running: connect Cursor Remote-SSH to Nebius VM and forward ports
3000, 9090, 3001, 8000, 8001.
EOF
    ;;
esac
