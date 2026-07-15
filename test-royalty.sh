#!/bin/bash
# End-to-end test: trigger the orchestrator -> it publishes to RabbitMQ -> consumer writes findw.payouts.
# Usage: bash test-royalty.sh [year month]   (default: all-time)
set -uo pipefail
Y="${1:-}"; M="${2:-}"
QS=""; [ -n "$Y" ] && [ -n "$M" ] && QS="?year=$Y&month=$M"

read NS ROUTE < <(kubectl get httproute -A --no-headers 2>/dev/null | awk '/royalty-orchestrator/{print $1,$2; exit}')
[ -n "${ROUTE:-}" ] || { echo "royalty-orchestrator route not found — is it deployed?"; exit 1; }
HOST=$(kubectl get httproute "$ROUTE" -n "$NS" -o jsonpath='{.spec.hostnames[0]}')
PREFIX=$(kubectl get httproute "$ROUTE" -n "$NS" -o jsonpath='{.spec.rules[0].matches[0].path.value}'); PREFIX="${PREFIX%/}"

kubectl port-forward -n openchoreo-data-plane svc/gateway-default 19080:19080 >/tmp/gw-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 4

echo "==> Trigger orchestrator: POST /orchestrator/run$QS"
curl -s -X POST -H "Host: $HOST" "http://localhost:19080${PREFIX}/orchestrator/run${QS}"; echo
echo "==> Wait for the consumer to process the queue..."; sleep 4

echo "==> findw.payouts (written by the consumer worker):"
kubectl exec -n authentic-photos-data-dev statefulset/mysql -- sh -c \
  'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT photographer, period, ROUND(revenue_cents/100,2) revenue, ROUND(royalty_cents/100,2) royalty, status, created_at FROM findw.payouts ORDER BY created_at DESC LIMIT 20;"' 2>/dev/null
echo
echo "If you see payout rows, the full chain works: Orchestrator -> RabbitMQ -> Consumer -> warehouse."
