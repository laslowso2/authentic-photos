# Phase 6 — DEV/QA/PROD Promotion + Memory Autoscaling

**Goal:** show OpenChoreo's platform value — one artifact promoted across environments with per-environment config, and memory-based autoscaling of the API.

**Exit criteria:** the same release runs in `development`, `qa`, and `production`, each talking to its own database with different replicas/resources; and the dev API scales out under memory load.

---

## Part A — QA environment + dev→qa→prod pipeline

```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-phase6-envs.sh
kubectl get environments -A
```
Creates the `qa` Environment, a `development→qa→production` DeploymentPipeline, and repoints the Project at it (was `default` = dev→staging→prod).

## Part B — Promote the API (per-environment config + DB)

Same release, different binding per environment. Each `ReleaseBinding` uses `workloadOverrides.env` to point at that environment's database, and `componentTypeEnvironmentConfigs` for replicas/resources.

```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/promote-phase6.sh qa
bash ~/Documents/Claude/OpenChoreo/authentic-photos/promote-phase6.sh prod
bash ~/Documents/Claude/OpenChoreo/authentic-photos/verify-phase6.sh
```
Each `promote-phase6.sh` (1) brings up that environment's MySQL (Phase 1 overlay), (2) reads the release currently in `development`, (3) binds that same release to the target environment. `verify-phase6.sh` hits each environment's `/health` — you should see `development` / `qa` / `production` reported by the same image, and prod running **2 replicas**.

**What this demonstrates:** identical container image, promoted unchanged; only the injected config (DB host/credentials, replica count, resource limits) differs per environment. That's the "config changes between DEV/QA/PROD" story.

## Part C — Memory-based autoscaling (dev)

The API now has a demo `/alloc` endpoint (holds memory on request). Rebuild it via CI so the running image has it, then add the HPA and drive load:

```bash
# 1) ship the /alloc endpoint through the CI pipeline (rebuilds + redeploys dev)
git -C ~/Documents/Claude/OpenChoreo/authentic-photos commit -am "add /alloc for autoscaling demo"
git -C ~/Documents/Claude/OpenChoreo/authentic-photos push
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-phase3.sh https://github.com/laslowso2/authentic-photos
# wait for the build to finish (bash verify-phase3.sh)

# 2) add the memory HPA to the dev deployment
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-hpa.sh

# 3) drive memory up and watch it scale (open a 2nd terminal for the watch if you like)
bash ~/Documents/Claude/OpenChoreo/authentic-photos/loadtest.sh
```
Expect `kubectl get hpa` `TARGETS` memory% to jump past 70% and `REPLICAS` to climb 1 → 2+.

---

## Honest notes / things to watch
1. **HPA vs the platform controller (the flag from discovery).** OpenChoreo's `renderedrelease-controller` manages the deployment, including `.spec.replicas`. A hand-applied HPA can contend with it — you may see replicas briefly reset. If that happens, it's expected: the *production-correct* fix is a platform-engineer-authored **autoscaling Trait** so OpenChoreo renders the HPA itself and doesn't double-manage replicas. Our plain HPA is the pragmatic demo of the same behavior.
2. **`workloadOverrides.env` shape.** The docs show env overrides via `--set spec.workloadOverrides.env.KEY=value`; we express that as a map in YAML. If a qa/prod binding doesn't pick up the DB override (health shows the wrong env/DB), tell me and we'll adjust the structure (it may need list form).
3. **qa/prod are not yet OAuth-gated.** The Phase 4 JWT policy was applied only to the dev route. To protect qa/prod too, re-run the Phase 4 policy against those routes (their generated namespaces). Optional for this phase.
4. **`/alloc` is demo-only** — it deliberately holds memory. Don't leave it in a real service. Caps: mb≤400, secs≤180.
5. **Memory limits.** Dev pods have a 256Mi limit; `loadtest.sh` allocates 180MB (safe). Allocating more, or stacking allocations on one pod, can trigger an OOM kill — which is itself a useful thing to observe, but keep it in mind.

---

## Reference docs
- Deploy and promote — https://openchoreo.dev/docs/developer-guide/deploying-applications/deploy-and-promote/
- Environment overrides — https://openchoreo.dev/docs/developer-guide/deploying-applications/environment-overrides/
- HPA (autoscaling/v2) — https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

## Next: Phase 5
The React web app + user login via Thunder (OIDC authorization-code) — the customer-facing side.
