#!/bin/bash
# Phase 4c: apply local rate limiting (250 req/min) to every Photos API route.
# Prints the live rateLimit schema first, then server-dry-runs before applying (fail-fast on schema mismatch).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMPL="$DIR/api/openchoreo/rate-limit.yaml"

echo "==> Live kgateway rateLimit schema (for reference / debugging):"
kubectl explain trafficpolicy.spec.rateLimit --recursive 2>/dev/null | head -40
echo

kubectl get httproute -A --no-headers | awk '/photos-api/{print $1, $2}' | while read -r NS ROUTE; do
  echo "==> $NS / $ROUTE"
  RENDERED=$(sed -e "s|__NS__|$NS|g" -e "s|__ROUTE__|$ROUTE|g" "$TMPL")
  # validate against the CRD first; if fields are wrong, this errors clearly and we stop.
  if ! echo "$RENDERED" | kubectl apply --dry-run=server -f - >/dev/null 2>/tmp/rl-err; then
    echo "   SCHEMA MISMATCH — the cluster rejected the rateLimit fields:"; cat /tmp/rl-err | sed 's/^/     /'
    echo "   Paste the schema above + this error and I'll correct rate-limit.yaml."
    exit 1
  fi
  echo "$RENDERED" | kubectl apply -f - >/dev/null
  echo "   applied"
done

echo
echo "Check attachment:  kubectl get trafficpolicy -A | grep photos-api"
echo "Test it:           bash $DIR/test-ratelimit.sh"
