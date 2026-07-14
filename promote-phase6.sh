#!/bin/bash
# Phase 6b: promote the current release to qa or prod (with that env's DB + config).
# Usage: bash promote-phase6.sh qa      (later: bash promote-phase6.sh prod)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV="${1:-}"
case "$ENV" in
  qa)   DBENV=qa;   FILE="$DIR/openchoreo/releasebindings/photos-api-qa.yaml";;
  prod) DBENV=prod; FILE="$DIR/openchoreo/releasebindings/photos-api-prod.yaml";;
  *) echo "Usage: bash promote-phase6.sh [qa|prod]"; exit 1;;
esac

echo "==> 1) Ensure the $DBENV database is up (Phase 1 overlay)"
bash "$DIR/apply-phase1.sh" "$DBENV"

echo "==> 2) Find the release currently deployed in development"
REL=$(kubectl get releasebinding photos-api-development -n default -o jsonpath='{.spec.releaseName}')
[ -n "$REL" ] || { echo "   No dev release found."; exit 1; }
echo "   release = $REL"

echo "==> 3) Bind that same release to '$ENV' (its own DB + config)"
sed "s|__RELEASE__|$REL|g" "$FILE" | kubectl apply -f -

echo
echo "Watch it come up:"
echo "   kubectl get releasebinding -n default | grep photos-api"
echo "   kubectl get pods -A | grep photos-api"
echo "Confirm which DB each env talks to:  bash $DIR/verify-phase6.sh"
