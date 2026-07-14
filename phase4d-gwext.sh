#!/bin/bash
# Phase 4d: get the kgateway GatewayExtension schema (holds JWT/JWKS config that jwtAuth references).
set +e
OUT="$(dirname "$0")/phase4d-output.txt"
exec > >(tee "$OUT") 2>&1
sec(){ echo; echo "==================== $* ===================="; }

sec "1. GatewayExtension schema (full)"
kubectl explain gatewayextension.spec --recursive 2>/dev/null

sec "2. Any existing GatewayExtensions to model?"
kubectl get gatewayextensions.gateway.kgateway.dev -A 2>/dev/null
kubectl get gatewayextensions.gateway.kgateway.dev -A -o yaml 2>/dev/null | sed -n '1,120p'

sec "3. What kind does jwtAuth.extensionRef expect?"
kubectl explain trafficpolicy.spec.jwtAuth.extensionRef 2>/dev/null

echo; echo "Done -> $OUT. Share it back."
