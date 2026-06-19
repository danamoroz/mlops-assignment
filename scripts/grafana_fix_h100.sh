#!/usr/bin/env bash
# Reset Grafana home dashboard and print access instructions for H100.
#
# H100 Grafana has ONE user: admin / admin
# If you see "Dashboard not found", you are likely hitting LOCAL Grafana (WSL)
# on the same localhost:3000, or a stale bookmark from local dev.
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
AUTH="admin:admin"

echo "=== Grafana H100 fix ==="
echo

if ! curl -sf -u "$AUTH" "$GRAFANA_URL/api/health" >/dev/null; then
  echo "ERROR: Grafana not reachable at $GRAFANA_URL"
  echo "Start stack: sudo docker compose up -d grafana"
  exit 1
fi

echo "--- Dashboards on THIS Grafana instance ---"
curl -s -u "$AUTH" "$GRAFANA_URL/api/search?type=dash-db" | python3 -c "
import sys, json
items = json.load(sys.stdin)
if not items:
    print('  (none — check provisioning / restart grafana)')
else:
    for d in items:
        print(f\"  {d['title']}\")
        print(f\"    URL: {d['url']}\")
        print(f\"    UID: {d['uid']}\")
"

echo
echo "--- Users on THIS instance ---"
curl -s -u "$AUTH" "$GRAFANA_URL/api/users/search" | python3 -c "
import sys, json
for u in json.load(sys.stdin).get('users', []):
    print(f\"  login={u['login']}  admin={u['isAdmin']}\")
"

echo
echo "--- Resetting home dashboard to vLLM serving ---"
curl -sf -X PUT -u "$AUTH" -H 'Content-Type: application/json' \
  "$GRAFANA_URL/api/org/preferences" \
  -d '{"homeDashboardUID":"vllm-serving"}' >/dev/null
curl -sf -X PUT -u "$AUTH" -H 'Content-Type: application/json' \
  "$GRAFANA_URL/api/user/preferences" \
  -d '{"homeDashboardUID":"vllm-serving"}' >/dev/null
echo "  OK  org + user home → vllm-serving"

echo
echo "=== How to open the dashboard ==="
echo
echo "  URL:    $GRAFANA_URL/d/vllm-serving/vllm-serving"
echo "  Login:  admin / admin   (only user on H100 — not your local dev user)"
echo "  Browse: $GRAFANA_URL/dashboards"
echo
echo "If you still get 'Dashboard not found':"
echo "  1. Stop LOCAL docker on your laptop/WSL:  docker compose down"
echo "     (local Grafana also binds :3000 and has a different database/users)"
echo "  2. Confirm port 3000 forwards to the H100 VM (Cursor Ports panel)"
echo "  3. Incognito window → admin/admin → use the URL above"
echo "  4. Clear site data for localhost:3000 (old bookmarks use deleted UIDs)"
echo
echo "Verify you hit H100 Grafana (run on laptop with port forward):"
echo "  curl -s -u admin:admin http://localhost:3000/api/search?type=dash-db"
echo "  → should list 'vLLM serving'"
