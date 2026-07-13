# Phase 2 — Node/TypeScript API Service

**Goal:** build the Photos API, deploy it as an OpenChoreo Component (`deployment/service`) in the development environment, wire it to the dev MySQL, and get `GET /photos` returning the seeded data.

**Exit criteria:** `GET /photos` (via port-forward) returns the 6 seeded photos, and `GET /health` reports `db: up`.

**Prerequisite:** Phase 1 dev database running (`bash verify-phase1.sh dev` shows 6 photos).

---

## The API in brief

A small Express + TypeScript service (`api/`) with three routes:

| Route | Purpose |
|---|---|
| `GET /health` | Liveness + DB reachability (`SELECT 1`) |
| `GET /photos` | List active photos (price returned in dollars) |
| `GET /photos/:id` | One photo by id |

It reads **all** config from environment variables (`api/src/config.ts`) — DB host, credentials, port. That's the key to the OpenChoreo story: the *same image* runs in dev/qa/prod, and only the injected env differs. The compile was verified clean before hand-off.

---

## How it gets onto the cluster (deploy-from-image)

We build the image locally and **import it into k3d** rather than pushing to a registry. k3d nodes run their own containerd, so they can't see your Docker images until imported. Because we tag it `:0.1.0` (not `:latest`), Kubernetes' default pull policy is `IfNotPresent` — it uses the imported image instead of trying to pull from a registry.

```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/build-and-deploy-dev.sh
```

This (1) `docker build`s the image, (2) `k3d image import`s it into cluster `openchoreo`, (3) `kubectl apply`s the Component + Workload. With `autoDeploy: true`, OpenChoreo creates a release and deploys it to the **development** environment automatically.

Watch it come up:
```bash
kubectl get pods -A | grep photos-api
```

## Verify

```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/verify-phase2.sh
```
It finds the API pod, port-forwards `localhost:18080 → 8080`, and curls the three routes. Success looks like `/health → {"db":"up"}` and `/photos → 6 photos`.

---

## Troubleshooting (two likely snags)

### A) Pod stuck in `ImagePullBackOff` / `ErrImagePull`
Means Kubernetes is trying to *pull* `authentic-photos/photos-api:0.1.0` from a registry. Two checks:

1. Confirm the image was imported:
   ```bash
   docker exec k3d-openchoreo-server-0 crictl images | grep photos-api
   ```
   If missing, re-run: `k3d image import authentic-photos/photos-api:0.1.0 -c openchoreo`.
2. If it's imported but still pulling, the ComponentType may default the pull policy to `Always`. See the schema:
   ```bash
   kubectl get clustercomponenttype service -o yaml | grep -i -A2 pullpolicy
   ```
   Tell me what it shows and I'll give you the exact `spec.parameters` to set `IfNotPresent` on the Component. Quick unblock in the meantime (patch the rendered Deployment — replace `<ns>`/`<deploy>` from `kubectl get deploy -A | grep photos-api`):
   ```bash
   kubectl -n <ns> patch deploy <deploy> --type=json \
     -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]'
   ```

### B) Pod runs but `/health` shows `db: down` (or `/photos` returns 500)
The API can't reach MySQL across namespaces. First, open the DB's port to the app namespace:
```bash
kubectl apply -f ~/Documents/Claude/OpenChoreo/authentic-photos/api/openchoreo/netpol-db-allow-dev.yaml
```
Re-run `verify-phase2.sh`. If it *still* fails, test connectivity from inside the API pod (replace `<ns>`/`<pod>`):
```bash
kubectl exec -n <ns> <pod> -- sh -c 'node -e "require(\"net\").connect(3306,\"mysql.authentic-photos-data-dev.svc.cluster.local\").on(\"connect\",()=>{console.log(\"OK\");process.exit(0)}).on(\"error\",e=>{console.log(\"FAIL\",e.message);process.exit(1)})"'
```
- `OK` but health still down → credentials/DB name mismatch (check the env in `component.yaml` vs the dev Secret).
- `FAIL` → egress from the OpenChoreo app namespace is blocked. Paste me the output and I'll provide the matching egress NetworkPolicy.

### C) Pod `CrashLoopBackOff`
```bash
kubectl logs -n <ns> <pod> --previous | tail -30
```
Send me the tail and I'll diagnose.

---

## What this phase demonstrates
- A real service deployed through OpenChoreo's Component/Workload abstraction — you wrote app code + a Workload, and the platform generated the Deployment, Service, and gateway route.
- **Config as environment**: the image is environment-agnostic; the DB target is injected. This is the foundation for the dev/qa/prod config story we complete in Phase 6.

## Reference docs
- Creating a Component — https://openchoreo.dev/docs/developer-guide/projects-and-components/creating-a-component/
- Define your workload — https://openchoreo.dev/docs/developer-guide/workload/overview/
- k3d image import — https://k3d.io/stable/usage/commands/k3d_image_import/

## Next: Phase 3
Switch the API from deploy-from-image to **build-from-source**: push `api/` to a Git repo, point a `dockerfile-builder` workflow at it, and let a `git push` trigger the build + deploy — the CI/CD story.
