# Phase 1 — Project + MySQL Database (per environment)

**Goal:** create the OpenChoreo Project that holds our components, and stand up a MySQL database — **one instance per environment (dev/qa/prod)** — with schema and sample photos, ready for the API service in Phase 2.

**Exit criteria:** the `authentic-photos` project exists, and the **dev** MySQL is running with 4 tables and 6 sample photos. (qa/prod are one command away when you want them.)

---

## How DEV/QA/PROD separation works here

Each environment gets its **own MySQL instance, in its own namespace, with its own credentials and volume**:

```
authentic-photos-data-dev    mysql StatefulSet + volume + dev creds
authentic-photos-data-qa     mysql StatefulSet + volume + qa creds
authentic-photos-data-prod   mysql StatefulSet + volume + prod creds  (more memory/storage)
```

The MySQL definition is written **once** (in `db/base/`) and each environment is a thin **kustomize overlay** (`db/overlays/{dev,qa,prod}/`) that only sets the namespace, the credentials, and — for prod — bigger resources. No copy-paste; change the base once and all envs inherit it.

Data is **never** promoted between environments (dev never gets prod data) — promotion applies to code and config, not database contents. The "config changes between DEV/QA/PROD" story then lands at the **API layer** in later phases: the API is an OpenChoreo component whose ReleaseBinding injects a different DB host + credentials per environment (dev API → dev DB, prod API → prod DB).

---

## Folder layout

```
authentic-photos/
├── openchoreo/project.yaml         # the OpenChoreo Project (shared by all envs)
└── db/
    ├── base/                       # MySQL defined once
    │   ├── kustomization.yaml      # builds initdb ConfigMap from the SQL below
    │   ├── schema.sql              # tables: photos, customers, orders, licenses
    │   ├── seed.sql                # 6 sample photos + 1 demo customer
    │   ├── 30-service.yaml         # mysql-headless + mysql services
    │   └── 40-statefulset.yaml     # MySQL 8.4 + 1Gi volume
    └── overlays/
        ├── dev/                    # -> namespace authentic-photos-data-dev
        ├── qa/                     # -> namespace authentic-photos-data-qa
        └── prod/                   # -> namespace authentic-photos-data-prod (bigger resources)
```
(The old `db/k8s/` folder is superseded — you can delete it.)

### Design note: why MySQL is *not* an OpenChoreo component
Phase 0 confirmed this install has **no `Resource`/`ResourceType` (managed-DB) abstraction** and **no StatefulSet ComponentType** (only Deployment/CronJob types). So we run MySQL as plain Kubernetes — which is also the realistic pattern: production databases are external managed infra (RDS/Cloud SQL) that OpenChoreo apps *depend on*, not something the platform runs statelessly. See the plan doc's pros/cons table for the full reasoning.

---

## Run it (dev first)

Make sure OpenChoreo is up (`~/restart-choreo.sh`), then:

```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/apply-phase1.sh dev
bash ~/Documents/Claude/OpenChoreo/authentic-photos/verify-phase1.sh dev
```

What `apply-phase1.sh dev` does:
1. `kubectl apply` the Project CR (once) — `authentic-photos` now appears in Backstage.
2. `kubectl apply -k db/overlays/dev` — kustomize renders the namespace, credentials Secret, the `mysql-initdb` ConfigMap (built from `schema.sql` + `seed.sql`), both Services, and the StatefulSet, all into `authentic-photos-data-dev`.
3. Waits for MySQL to report ready. On first boot MySQL auto-runs the init SQL (`/docker-entrypoint-initdb.d`), so the tables and sample photos are there immediately.

When you're ready for the other environments:
```bash
bash apply-phase1.sh qa
bash apply-phase1.sh prod
```

## Verify it

`verify-phase1.sh dev` prints the project, the running `mysql-0` pod, the 4 tables, the 6 photos, and confirms the app user can connect. You can also open Backstage (`http://openchoreo.localhost:8080`) and find **Authentic Photos** in the Catalog.

---

## Things to know / gotchas

- **Init SQL runs only on first boot** (empty volume). To reload after editing SQL:
  ```bash
  kubectl delete statefulset mysql -n authentic-photos-data-dev
  kubectl delete pvc data-mysql-0 -n authentic-photos-data-dev
  bash apply-phase1.sh dev
  ```
- **Money is stored as integer cents** (`price_cents`) to avoid floating-point rounding.
- **Cross-namespace connectivity** (API → MySQL) is validated in Phase 2. OpenChoreo applies network policies to app namespaces; if the API pod can't reach `mysql.authentic-photos-data-dev`, we add a small NetworkPolicy allowance. Flagged now so it's not a surprise.
- **Credentials are demo values** in each overlay's `kustomization.yaml` (`secretGenerator`). Fine for local learning; rotate and use a real secret manager beyond this.
- **kustomize is built into kubectl** (`kubectl apply -k`), so there's nothing extra to install.

---

## Reference docs
- Creating a Project — https://openchoreo.dev/docs/developer-guide/projects-and-components/creating-a-project/
- Developer abstractions — https://openchoreo.dev/docs/concepts/developer-abstractions/
- Kustomize (bases & overlays) — https://kubectl.docs.kubernetes.io/references/kustomize/
- MySQL image init behavior — https://hub.docker.com/_/mysql (see "Initializing a fresh instance")

---

## Next: Phase 2
Build the Node/TypeScript **API service**, containerize it, deploy it as an OpenChoreo Component (`deployment/service`) in the development environment, wire it to the dev database, confirm cross-namespace connectivity, and expose `GET /photos`.
