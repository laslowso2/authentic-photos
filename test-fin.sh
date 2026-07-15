#!/bin/bash
# Test the Ballerina DataService report endpoints through the gateway (open / no auth yet).
set -uo pipefail
read NS ROUTE < <(kubectl get httproute -A --no-headers 2>/dev/null | awk '/fin-dataservice/{print $1,$2; exit}')
[ -n "${ROUTE:-}" ] || { echo "fin-dataservice route not found — is it deployed?"; exit 1; }
HOST=$(kubectl get httproute "$ROUTE" -n "$NS" -o jsonpath='{.spec.hostnames[0]}')
PREFIX=$(kubectl get httproute "$ROUTE" -n "$NS" -o jsonpath='{.spec.rules[0].matches[0].path.value}'); PREFIX="${PREFIX%/}"
echo "route=$ROUTE host=$HOST prefix=$PREFIX"

kubectl port-forward -n openchoreo-data-plane svc/gateway-default 19080:19080 >/tmp/gw-pf.log 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 4

for ep in health summary revenueByMonth topPhotos revenueByLicense revenueByPhotographer; do
  echo "--- GET /reports/$ep ---"
  curl -s -H "Host: $HOST" "http://localhost:19080${PREFIX}/reports/$ep"; echo
done
echo "--- GET /reports/revenueByPhotographer?year=2026&month=6 ---"
curl -s -H "Host: $HOST" "http://localhost:19080${PREFIX}/reports/revenueByPhotographer?year=2026&month=6"; echo
echo
echo "revenueByPhotographer returning data => the rebuild landed (it feeds the royalty orchestrator)."
