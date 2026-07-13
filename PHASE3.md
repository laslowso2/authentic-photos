# Phase 3 — CI from Git (build-from-source)

**Goal:** stop building the image by hand. Push the code to GitHub, point the Component at the repo, and have **OpenChoreo build and deploy** it — the CI/CD story.

**Exit criteria:** a `WorkflowRun` clones the repo, builds the image, and the API redeploys from that built image; `GET /photos` still returns the 6 photos (now served by the OpenChoreo-built image).

**Prerequisite:** Phase 2 working (API deployed), and the `api/workload.yaml` descriptor present (it defines the endpoint + env vars for source builds).

---

## What changes vs Phase 2
| | Phase 2 (deploy-from-image) | Phase 3 (build-from-source) |
|---|---|---|
| Who builds the image | You (`docker build` + `k3d image import`) | **OpenChoreo** (clone → build → publish) |
| Trigger | `kubectl apply` | A **WorkflowRun** (or `git push` + webhook) |
| Endpoints & env | hand-written Workload CR | `api/workload.yaml` descriptor in the repo |

---

## Step 1 — Create an empty public GitHub repo
Either with the GitHub CLI:
```bash
gh repo create authentic-photos --public --disable-wiki
```
…or on github.com: **New repository → name `authentic-photos` → Public → Create** (don't add a README, keep it empty).

## Step 2 — Push the folder
```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/push-to-github.sh https://github.com/<you>/authentic-photos.git
```
This inits git, removes build artifacts, commits, and pushes to `main`. (You'll need GitHub auth set up — `gh auth login`, an SSH key, or a personal-access-token over HTTPS.)

## Step 3 — Switch to source-build and trigger a build
```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-phase3.sh https://github.com/<you>/authentic-photos
```
This updates the `photos-api` Component to build from your repo (`dockerfile-builder`, `appPath: /api`) and creates a `WorkflowRun` to kick off the build.

## Step 4 — Monitor the build
```bash
kubectl get workflowrun -n default -w                    # watch overall status
kubectl describe workflowrun <run-name> -n default       # see status.tasks: checkout-source, containerfile-build, publish-image, generate-workload-cr
```
Conditions progress `WorkflowRunning → WorkflowSucceeded`. To find live build logs (Argo pods run in the workflow plane):
```bash
kubectl get pods -A | grep -iE 'build|photos-api-build'
kubectl logs -n <that-namespace> <that-pod>
```

## Step 5 — Verify
Once the build succeeds and auto-deploys:
```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/verify-phase2.sh
```
Same result as Phase 2 — but the running image was built by OpenChoreo from your Git repo, not your laptop.

## Step 6 — Iterate (the CI loop)
Change code → commit/push → trigger a new build:
```bash
git -C ~/Documents/Claude/OpenChoreo/authentic-photos commit -am "tweak API"
git -C ~/Documents/Claude/OpenChoreo/authentic-photos push
bash deploy-phase3.sh https://github.com/<you>/authentic-photos   # creates a fresh WorkflowRun
```

### Optional: true auto-build on push
`autoBuild: true` is set, but a Git **webhook** must reach OpenChoreo — which it can't on `localhost`. To enable real push-to-deploy, expose the OpenChoreo webhook endpoint with a tunnel (e.g. `cloudflared tunnel` or `ngrok`) and register that URL as a webhook in the GitHub repo. Not required for the demo; the `WorkflowRun` trigger shows the same pipeline. See: https://openchoreo.dev/docs/developer-guide/workflows/ci/auto-build/

---

## Troubleshooting
- **`WorkflowNotAllowed` / `ComponentValidationFailed`**: the `service` ComponentType may not list `dockerfile-builder` in `allowedWorkflows`. Check:
  ```bash
  kubectl get clustercomponenttype service -o yaml | grep -i -A5 allowedWorkflows
  ```
  If it's missing, that's a platform-engineer setting — tell me and we adjust (or use the buildpacks workflow that is allowed).
- **Build fails at `checkout-source`**: repo URL/branch wrong, or the repo is private (needs `repository.secretRef`). Confirm the repo is public and the URL matches.
- **Build fails at `containerfile-build`**: Dockerfile path/context. We use `context: /api`, `filePath: /api/Dockerfile` — make sure `api/Dockerfile` was pushed.
- **`git push` rejected**: auth not set up — run `gh auth login` or add an SSH key / PAT.
- **Endpoint gone after switch**: ensure `api/workload.yaml` is in the repo at `api/` — without it the generated Workload has no endpoint.

---

## What this phase demonstrates
The CI/CD golden path: source in Git → OpenChoreo builds, versions, and deploys with no external CI system and no local Docker. The `workload.yaml` descriptor keeps the runtime contract (endpoints, env, dependencies) versioned alongside the code.

## Reference docs
- CI overview — https://openchoreo.dev/docs/developer-guide/workflows/ci/overview/
- Workload descriptor — https://openchoreo.dev/docs/developer-guide/workflows/ci/workload-descriptor/
- Auto-build — https://openchoreo.dev/docs/developer-guide/workflows/ci/auto-build/
- Private repo — https://openchoreo.dev/docs/developer-guide/workflows/ci/private-repository/

## Next: Phase 4
Publish the API through the gateway and add OAuth so external apps can **subscribe** and call it with a token (Thunder client-credentials + a kgateway JWT policy).
