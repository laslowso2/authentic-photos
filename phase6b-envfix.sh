#!/bin/bash
# Find the correct shape for per-environment env-var overrides in a ReleaseBinding.
set +e
OUT="$(dirname "$0")/phase6b-output.txt"
exec > >(tee "$OUT") 2>&1
sec(){ echo; echo "==================== $* ===================="; }

sec "1. ReleaseBinding.spec top-level fields"
kubectl explain releasebinding.spec 2>/dev/null | grep -E '^  [a-zA-Z]'

sec "2. workloadOverrides schema (full/recursive)"
kubectl explain releasebinding.spec.workloadOverrides --recursive 2>/dev/null

sec "3. What actually got stored on the qa binding (did it keep my map?)"
kubectl get releasebinding photos-api-qa -n default -o jsonpath='{.spec.workloadOverrides}' 2>/dev/null; echo

sec "4. For reference: how env looks in the Workload (key/value list)"
kubectl get workload photos-api-workload -n default -o jsonpath='{.spec.container.env}' 2>/dev/null; echo

echo; echo "Done -> $OUT. Share it back and I'll fix the qa/prod bindings."
