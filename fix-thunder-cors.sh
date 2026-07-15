#!/bin/bash
# Phase 5 Stage 3 fix: allow the web app origin in Thunder's CORS config, then restart Thunder.
# (Cleans up any prior malformed entry for this host, then inserts a correctly-quoted one.)
set -euo pipefail

WNS=$(kubectl get httproute -A --no-headers | awk '/photos-web/{print $1; exit}')
WRT=$(kubectl get httproute -A --no-headers | awk '/photos-web/{print $2; exit}')
WHOST=$(kubectl get httproute "$WRT" -n "$WNS" -o jsonpath='{.spec.hostnames[0]}')
ORIGIN="http://$WHOST:19080"
echo "==> Thunder CORS origin: $ORIGIN"

kubectl get configmap thunder-config-map -n thunder -o json \
 | ORIGIN="$ORIGIN" MARKER="$WHOST" python3 -c '
import json, sys, os, re
cm = json.load(sys.stdin)
origin = os.environ["ORIGIN"]; marker = os.environ["MARKER"]
dep = cm["data"]["deployment.yaml"]
# drop any existing line that references our web host (correct or malformed)
dep = "\n".join(l for l in dep.split("\n") if marker not in l)
# insert a correctly-quoted entry right after the FIRST allowed_origins: (the cors block)
dep = re.sub(r"(allowed_origins:\n)", lambda m: m.group(1) + "    - \"" + origin + "\"\n", dep, count=1)
cm["data"]["deployment.yaml"] = dep
json.dump(cm, sys.stdout)
' | kubectl apply -f - >/dev/null

echo "==> Show the cors block now:"
kubectl get cm thunder-config-map -n thunder -o jsonpath='{.data.deployment\.yaml}' | grep -A5 'cors:'

echo "==> Restart Thunder"
kubectl rollout restart deployment/thunder-deployment -n thunder
kubectl rollout status deployment/thunder-deployment -n thunder --timeout=120s
sleep 3

echo "==> CORS header check (want Access-Control-Allow-Origin):"
curl -s -D - -o /dev/null -H "Origin: $ORIGIN" \
  http://thunder.openchoreo.localhost:8080/.well-known/openid-configuration | grep -iE 'HTTP/|access-control' || true
echo
echo "If you see access-control-allow-origin above, reload the web app and log in."
