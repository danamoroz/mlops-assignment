#!/usr/bin/env bash
# Phase 2 verification — metrics pipeline + PromQL for all serving.json panels.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

fail=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  OK  $label"
  else
    echo "  FAIL  $label"
    fail=1
  fi
}

echo "=== Phase 2 verify ==="
echo

echo "--- vLLM / Prometheus ---"
check "vLLM health" curl -sf http://localhost:8000/health
check "Prometheus up" curl -sf http://localhost:9090/-/ready

if curl -sf http://localhost:9090/api/v1/targets >/dev/null; then
  health="$(curl -s http://localhost:9090/api/v1/targets | python3 -c "
import sys, json
d = json.load(sys.stdin)
t = [x for x in d['data']['activeTargets'] if x.get('labels', {}).get('job') == 'vllm']
print(t[0]['health'] if t else 'missing')
")"
  if [[ "$health" == "up" ]]; then
    echo "  OK  Prometheus target vllm"
  else
    echo "  FAIL  Prometheus target vllm ($health)"
    fail=1
  fi
fi

echo
echo "--- Grafana dashboard ---"
if curl -sf -u admin:admin http://localhost:3000/api/dashboards/uid/vllm-serving >/dev/null; then
  curl -s -u admin:admin http://localhost:3000/api/dashboards/uid/vllm-serving | python3 -c "
import sys, json
d = json.load(sys.stdin)['dashboard']
rows = [p['title'] for p in d['panels'] if p.get('type') == 'row']
panels = [p['title'] for p in d['panels'] if p.get('type') != 'row']
print(f\"  OK  Dashboard: {d['title']} ({len(rows)} rows, {len(panels)} panels)\")
for r in rows:
    print(f\"      row: {r}\")
"
else
  echo "  FAIL  Grafana dashboard vllm-serving (login at http://localhost:3000 admin/admin)"
  fail=1
fi

echo
echo "--- PromQL (instant; run burst first if latency/KV panels empty) ---"
python3 <<'PY'
import json, sys, urllib.parse, urllib.request

queries = {
    "TTFT p95": "histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))",
    "E2E p95": "histogram_quantile(0.95, sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket[5m])))",
    "Prefill p95": "histogram_quantile(0.95, sum by (le) (rate(vllm:request_prefill_time_seconds_bucket[5m])))",
    "Gen tok/s": "rate(vllm:generation_tokens_total[1m])",
    "Success/s": "sum(rate(vllm:request_success_total[1m]))",
    "GPU KV cache": "vllm:gpu_cache_usage_perc",
    "Preemptions/s": "rate(vllm:num_preemptions_total[1m])",
}

fail = False
for name, q in queries.items():
    url = "http://localhost:9090/api/v1/query?" + urllib.parse.urlencode({"query": q})
    try:
        data = json.load(urllib.request.urlopen(url, timeout=10))
    except Exception as e:
        print(f"  FAIL  {name}: {e}")
        fail = True
        continue
    res = data.get("data", {}).get("result", [])
    if not res:
        print(f"  WARN  {name}: no data (run: bash scripts/burst_vllm_load.sh all)")
        continue
    vals = [float(s["value"][1]) for s in res if s.get("value")]
    if vals:
        print(f"  OK  {name}: {max(vals):.4g}")
    else:
        print(f"  WARN  {name}: empty values")

sys.exit(1 if fail else 0)
PY
py_fail=$?
[[ $py_fail -ne 0 ]] && fail=1

echo
if [[ $fail -eq 0 ]]; then
  echo "Phase 2 automated checks passed."
  echo "Manual: capture screenshots/grafana_serving.png — bash scripts/phase2_screenshot_helper.sh"
else
  echo "Phase 2 checks failed — fix issues above."
  exit 1
fi
