#!/bin/bash
# Phase 6c: apply the memory HPA to the development Photos API deployment.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
read NS DEPLOY < <(kubectl get deploy -A --no-headers 2>/dev/null | awk '/photos-api-development/{print $1,$2; exit}')
[ -n "${DEPLOY:-}" ] || { echo "dev deployment not found"; exit 1; }
echo "==> HPA target: $NS / $DEPLOY"
sed -e "s|__NS__|$NS|g" -e "s|__DEPLOY__|$DEPLOY|g" "$DIR/api/openchoreo/hpa.yaml" | kubectl apply -f -
echo
echo "Watch it:  kubectl get hpa photos-api-hpa -n $NS -w"
echo "Drive load: bash $DIR/loadtest.sh"
