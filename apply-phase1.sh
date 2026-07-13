#!/bin/bash
# Phase 1 apply: OpenChoreo Project + MySQL database (per environment) with schema & seed.
# Usage:  bash apply-phase1.sh [dev|qa|prod]     (default: dev)
# Example: bash ~/Documents/Claude/OpenChoreo/authentic-photos/apply-phase1.sh dev
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ENV="${1:-dev}"
case "$ENV" in dev|qa|prod) ;; *) echo "ENV must be dev, qa, or prod"; exit 1;; esac
NS="authentic-photos-data-$ENV"

echo "==> 1/3 Create the OpenChoreo Project 'authentic-photos' (once, shared by all envs)"
kubectl apply -f "$DIR/openchoreo/project.yaml"

echo "==> 2/3 Deploy the '$ENV' MySQL via kustomize (namespace + secret + configmap + services + statefulset)"
# One 'apply -k' renders the base with the env overlay. Peek at what will be applied:
kubectl kustomize "$DIR/db/overlays/$ENV" >/dev/null   # fails fast if the kustomization is invalid
kubectl apply -k "$DIR/db/overlays/$ENV"

echo "==> 3/3 Wait for MySQL to become ready (first boot runs schema + seed)..."
kubectl rollout status statefulset/mysql -n "$NS" --timeout=180s

echo
echo "Done ($ENV). Verify with: bash $DIR/verify-phase1.sh $ENV"
