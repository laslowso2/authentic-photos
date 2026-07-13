#!/bin/bash
# Phase 2 verification: find the API pod, port-forward, and hit the endpoints.
set -uo pipefail

echo "==> Locating the API pod (OpenChoreo runs it in a generated app namespace)..."
read NS POD < <(kubectl get pods -A --no-headers 2>/dev/null | awk '/photos-api/{print $1, $2; exit}')
if [ -z "${POD:-}" ]; then
  echo "   Not found yet. Check:  kubectl get pods -A | grep photos-api"
  exit 1
fi
echo "   Found: pod/$POD  in namespace  $NS"

echo "==> Pod status:"
kubectl get pod "$POD" -n "$NS"

echo "==> Waiting for readiness (up to 60s)..."
kubectl wait -n "$NS" --for=condition=ready pod/"$POD" --timeout=60s || \
  echo "   (not ready — endpoints below may fail; see PHASE2 troubleshooting)"

echo "==> Port-forwarding localhost:18080 -> pod:8080 ..."
kubectl port-forward -n "$NS" "pod/$POD" 18080:8080 >/tmp/photos-api-pf.log 2>&1 &
PF=$!
sleep 4

echo "--- GET /health ---";      curl -s --max-time 8 localhost:18080/health;    echo
echo "--- GET /photos ---";      curl -s --max-time 8 localhost:18080/photos;    echo
echo "--- GET /photos/3 ---";    curl -s --max-time 8 localhost:18080/photos/3;  echo

kill $PF 2>/dev/null
echo
echo "Expect /health -> db:up, and /photos -> 6 photos. If db is down, see PHASE2 troubleshooting."
