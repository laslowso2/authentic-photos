#!/bin/bash
# Phase 5 Stage 3: add CORS on the dev API route allowing the web app origin.
# Prints the live cors schema + server-dry-runs before applying (fail-fast on schema mismatch).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMPL="$DIR/api/openchoreo/cors-policy.yaml"

# dev API route
read NS ROUTE < <(kubectl get httproute -A --no-headers | awk '/photos-api/ && $1 ~ /-development-/{print $1,$2; exit}')
# web app origin
WNS=$(kubectl get httproute -A --no-headers | awk '/photos-web/{print $1; exit}')
WRT=$(kubectl get httproute -A --no-headers | awk '/photos-web/{print $2; exit}')
WHOST=$(kubectl get httproute "$WRT" -n "$WNS" -o jsonpath='{.spec.hostnames[0]}')
ORIGIN="http://$WHOST:19080"
echo "==> API route: $NS/$ROUTE    web origin: $ORIGIN"

echo "==> Live kgateway cors schema (reference):"
kubectl explain trafficpolicy.spec.cors --recursive 2>/dev/null | head -30
echo

RENDERED=$(sed -e "s|__NS__|$NS|g" -e "s|__ROUTE__|$ROUTE|g" -e "s|__ORIGIN__|$ORIGIN|g" "$TMPL")
if ! echo "$RENDERED" | kubectl apply --dry-run=server -f - >/dev/null 2>/tmp/cors-err; then
  echo "SCHEMA MISMATCH — cluster rejected the cors fields:"; sed 's/^/   /' /tmp/cors-err
  echo "Paste the schema above + this error and I'll correct cors-policy.yaml."
  exit 1
fi
echo "$RENDERED" | kubectl apply -f -
echo; echo "CORS applied for $ORIGIN"
