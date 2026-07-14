#!/bin/bash
# Phase 6 verification: same release in dev/qa/prod, each reporting its own environment + DB.
set -uo pipefail

echo "==> ReleaseBindings (same releaseName across environments = one artifact):"
kubectl get releasebinding -n default -o custom-columns=\
NAME:.metadata.name,ENV:.spec.environment,RELEASE:.spec.releaseName,STATE:.spec.state 2>/dev/null | grep -E 'NAME|photos-api'

echo
for E in development qa production; do
  NS=$(kubectl get pods -A --no-headers 2>/dev/null | awk -v e="authentic-pho-${E}" '$1 ~ e {print $1; exit}')
  [ -z "$NS" ] && { echo "== $E: no pod yet =="; continue; }
  POD=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | awk '/photos-api/{print $1; exit}')
  CNT=$(kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -c photos-api)
  echo "== $E  (ns=$NS, replicas running=$CNT) =="
  kubectl port-forward -n "$NS" "pod/$POD" 18090:8080 >/tmp/v6-pf.log 2>&1 &
  PF=$!; sleep 3
  echo -n "   /health -> "; curl -s --max-time 6 localhost:18090/health; echo
  kill $PF 2>/dev/null; sleep 1
done
echo
echo "Each environment should report its own APP_ENV (development/qa/production) and db:up —"
echo "same image, different injected config + database. Prod should show 2 replicas."
