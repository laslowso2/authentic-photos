# Authentic Photos on OpenChoreo — PLAYBOOK

**A single-source manual to recreate the whole solution from zero.**
Everything is here: architecture, the facts about this specific cluster, every command, every script, and every file's full contents (Appendix B). If you delete the folder, you can rebuild it from this document alone.

- **Last updated:** for OpenChoreo v1.1.x on local k3d (Colima).
- **What's built so far:** Phase 0 (discovery), Phase 1 (Project + MySQL per env), Phase 2 (Node/TS API), Phase 3 (CI from Git — OpenChoreo builds & deploys), Phase 4 (OAuth-protected API + external subscription), Phase 6 Part A+B (qa env, dev→qa→prod pipeline, same release promoted across dev/qa/prod with per-env DB + replicas). Phase 4c (local rate limiting, 250 req/min) DONE. Remaining: Phase 6 Part C (autoscaling), Phase 5 (web app + login).
- **Delivery model:** manifests + code + scripts live in `~/Documents/Claude/OpenChoreo/authentic-photos/`. You run the commands against your own cluster.

---

## 1. What we're building

A small "Authentic Photos" store that demonstrates OpenChoreo's benefits: source-to-deploy CI/CD, DEV/QA/PROD config, memory-based autoscaling, and a managed OAuth API that external apps can subscribe to. Three deployable units in one OpenChoreo **Project**:

1. **MySQL** — photo metadata, orders, licenses (metadata-only; placeholder image URLs).
2. **API service (Node/TypeScript)** — the subscribable product; browse photos, order licensed copies.
3. **Web app (React)** — user login via Thunder (OIDC), calls the API with OAuth.

```
Browser ──login (Thunder OIDC)──► Web App ──OAuth token──► API Service ──► MySQL
External app ──subscribe + OAuth──► Gateway ──► API Service
```

### Mapping to OpenChoreo concepts
| Our thing | OpenChoreo abstraction |
|---|---|
| Whole app | **Project** `authentic-photos` |
| API service | **Component** (`deployment/service`) + **Workload** |
| Web app | **Component** (`deployment/web-application`) |
| MySQL | plain Kubernetes StatefulSet (see §3 note) |
| CI from Git | **Workflow** (`dockerfile-builder`) + **WorkflowRun** |
| DEV/QA/PROD | **Environments** + **DeploymentPipeline** |
| Per-env config | **ReleaseBinding** `environmentConfigs` |
| Autoscaling | HPA (added manually; no autoscaling Trait shipped) |
| Publish + subscribe | kgateway (Gateway API) + Thunder OAuth |
| Login | **Thunder** IdP (OIDC) |

---

## 2. Facts about THIS cluster (from Phase 0 discovery)

These shaped every design decision — verify they still hold if you rebuild on a different install:

- **No `occ` CLI installed** → we drive everything with `kubectl` (kustomize is built in via `kubectl -k`).
- **No `Resource`/`ResourceType` CRD** → there is no managed-database abstraction, so MySQL runs as plain Kubernetes.
- **ComponentTypes available:** `service` (deployment), `web-application` (deployment), `worker` (deployment), `scheduled-task` (cronjob). No StatefulSet type.
- **Traits available:** only `observability-alert-rule`. No autoscaling trait → we add a plain `HorizontalPodAutoscaler`.
- **Environments:** `development`, `staging`, `production`; pipeline `default`. (We add a `qa` env in Phase 6.)
- **Gateway:** kgateway + Gateway API (`httproutes`, `gateways`, `trafficpolicies`). No WSO2-style "subscription" CRD → subscription = Thunder OAuth client + gateway JWT policy.
- **Thunder IdP:** running in namespace `thunder`, public URL `http://thunder.openchoreo.localhost:8080`, service `thunder-service:8090`. Supports OAuth2/OIDC (authorization-code, client-credentials, DCR).
- **Build workflows:** `dockerfile-builder`, `gcp-buildpacks-builder`, `paketo-buildpacks-builder`, `ballerina-buildpack-builder`.
- **Cluster name:** `openchoreo` (k3d). Reference project already present: `online-store` with `greeting-service` + `react-starter`.

### Rediscover any time (read-only)
```bash
kubectl get crds | grep -iE 'choreo|thunder' | sort         # all OC/Thunder kinds
kubectl get clustercomponenttypes                            # deployable templates
kubectl get clustertraits                                    # available traits
kubectl get environments -A; kubectl get deploymentpipelines -A
kubectl get clusterworkflows                                 # build workflows
kubectl get httproutes -A; kubectl get gateways -A           # how endpoints are exposed
```

---

## 3. Prerequisites & cold start

**Tools:** Docker (via Colima), `kubectl`, `k3d`, and the running OpenChoreo cluster.

**Bring OpenChoreo up after a reboot:**
```bash
~/restart-choreo.sh
```
This starts Colima, the k3d cluster, fixes CoreDNS host resolution, and restarts the control plane + Thunder. When done, Backstage is at `http://openchoreo.localhost:8080`.

### Design note — why MySQL is not an OpenChoreo component
This install has no managed-DB `Resource` abstraction and no StatefulSet ComponentType, so we run MySQL as plain Kubernetes. That's also the realistic production pattern: databases are external managed infra (RDS/Cloud SQL) that apps *depend on*, not something the platform runs statelessly. Environment separation still works: one DB instance per environment namespace. Data is never promoted between environments — only code/config is.

---

## 4. Folder layout

```
authentic-photos/
├── PLAYBOOK.md                     # this file
├── PHASE1.md, PHASE2.md            # per-phase runbooks
├── openchoreo/project.yaml         # the Project (shared by all envs)
├── apply-phase1.sh                 # deploy Project + MySQL for an env
├── verify-phase1.sh                # verify DB
├── build-and-deploy-dev.sh         # build API image, import to k3d, deploy
├── verify-phase2.sh                # verify API endpoints
├── db/
│   ├── base/                       # MySQL defined once
│   │   ├── kustomization.yaml
│   │   ├── schema.sql  seed.sql
│   │   ├── 30-service.yaml  40-statefulset.yaml
│   └── overlays/{dev,qa,prod}/     # per-env namespace + credentials
└── api/
    ├── package.json  tsconfig.json  Dockerfile  .dockerignore
    ├── src/{config.ts, db.ts, index.ts}
    └── openchoreo/{component.yaml, netpol-db-allow-dev.yaml}
```

---

## 5. Phase 0 — Discovery (read-only)
Confirm the cluster facts in §2. See the rediscover commands above, or the `phase0-discovery.sh` / `phase0b-discovery.sh` scripts. **Exit:** no unknowns about ComponentTypes, Traits, DB abstraction, gateway, or Thunder.

---

## 6. Phase 1 — Project + MySQL (per environment)

**Goal:** create the Project and stand up MySQL (schema + seed) per environment.

```bash
# dev first
bash ~/Documents/Claude/OpenChoreo/authentic-photos/apply-phase1.sh dev
bash ~/Documents/Claude/OpenChoreo/authentic-photos/verify-phase1.sh dev
# later:
bash apply-phase1.sh qa
bash apply-phase1.sh prod
```

What happens: applies the Project CR, then `kubectl apply -k db/overlays/dev` renders the namespace, credentials Secret, an `mysql-initdb` ConfigMap built from `schema.sql`+`seed.sql`, the Services, and the StatefulSet into `authentic-photos-data-dev`. MySQL auto-runs the init SQL on first boot.

**Verify success:** 4 tables (`photos, customers, orders, licenses`) and 6 photos.

**Gotchas:**
- Init SQL runs only on an empty volume. To reload after editing SQL:
  ```bash
  kubectl delete statefulset mysql -n authentic-photos-data-dev
  kubectl delete pvc data-mysql-0 -n authentic-photos-data-dev
  bash apply-phase1.sh dev
  ```
- MySQL 8.4 removed `--default-authentication-plugin` — do **not** pass it (caching_sha2_password is default). (This caused a CrashLoopBackOff during the original build.)

---

## 7. Phase 2 — Node/TypeScript API (deploy-from-image)

**Goal:** deploy the API as an OpenChoreo Component wired to the dev DB; `GET /photos` returns seeded data.

```bash
bash ~/Documents/Claude/OpenChoreo/authentic-photos/build-and-deploy-dev.sh
kubectl get pods -A | grep photos-api          # watch it come up
bash ~/Documents/Claude/OpenChoreo/authentic-photos/verify-phase2.sh
```

The build script: `docker build` the image → `k3d image import authentic-photos/photos-api:0.1.0 -c openchoreo` (nodes can't see local Docker images otherwise) → `kubectl apply` the Component + Workload. `autoDeploy: true` deploys to the development environment.

**UI equivalent:** Backstage → Create Component → "Container Image" → name `photos-api`, image `authentic-photos/photos-api:0.1.0`, Auto Deploy on; Step 3 add HTTP endpoint 8080 + the DB env vars. Same resulting `Component`+`Workload` CRs. Note: the UI does **not** build or import the image — you'd still run `docker build` + `k3d image import` first for a local image.

**Verify success:** `/health → db:up`, `/photos → 6 photos`.

**Troubleshooting:**
- `ImagePullBackOff`: confirm import with `docker exec k3d-openchoreo-server-0 crictl images | grep photos-api`; check pull policy `kubectl get clustercomponenttype service -o yaml | grep -i -A2 pullpolicy`. Patch a rendered Deployment: `kubectl -n <ns> patch deploy <deploy> --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]'`.
- `/health db:down`: apply the DB NetworkPolicy `kubectl apply -f api/openchoreo/netpol-db-allow-dev.yaml`, re-verify. If still failing, egress from the app namespace is blocked — capture pod connectivity test (in PHASE2.md) and add an egress policy.
- `CrashLoopBackOff`: `kubectl logs -n <ns> <pod> --previous | tail -30`.

---

## 8. Phase 3 — CI from Git (DONE)

Push `api/` to a **public GitHub repo**; switch the Component to build-from-source (`component-from-source.yaml`, `dockerfile-builder`, `appPath: /api`); trigger builds with a `WorkflowRun` (`deploy-phase3.sh <repo-url>`). OpenChoreo clones → builds → publishes to its registry → auto-deploys. The runtime contract (endpoint + env) comes from `api/workload.yaml`. See `PHASE3.md`.

**Gotcha we hit — registry DNS (important):** the build's `publish-image` step pushes to `host.k3d.internal:10082`, but pods can't resolve that name — and k3s **reverts** edits to the coredns `NodeHosts` field. Fix by aliasing it in the reconcile-proof `coredns-custom` configmap:
```bash
kubectl patch configmap coredns-custom -n kube-system --type merge \
  -p '{"data":{"k3dhost.override":"rewrite stop {\n  name exact host.k3d.internal choreo-host\n  answer auto\n}\n"}}'
kubectl delete pod -n kube-system -l k8s-app=kube-dns
```
This is baked into `fix-registry-dns.sh` and made permanent in `restart-choreo.sh`. Verify with: pod `nslookup host.k3d.internal` → 172.18.0.1 and `nc -zv host.k3d.internal 10082` → open. Confirm the deploy flipped over: the running pod's image should read `host.k3d.internal:10082/default-authentic-photos-photos-api:v1-...` (via `verify-phase3.sh`).

Extra Phase-3 scripts: `push-to-github.sh`, `deploy-phase3.sh`, `verify-phase3.sh`, `fix-registry-dns.sh`, `diagnose-registry.sh`, `get-build-logs.sh`.

## 9. Phase 4 — OAuth-protected API + subscription (DONE)

External apps subscribe by registering a `client_credentials` app in **Thunder**, then call the API with a Bearer JWT that **kgateway** validates at the route. Flow: `app → Thunder /oauth2/token → JWT → gateway (validate issuer+aud+signature via JWKS) → API`. Result: **401 without token, 200 with token**. See `PHASE4.md`.

Scripts: `register-subscriber.sh`, `get-token.sh`, `deploy-phase4.sh`, `test-phase4.sh`; manifests `api/openchoreo/{thunder-subscriber-app.json, gateway-jwt.yaml}`.

**Phase 4b — per-environment isolation (DONE):** one OAuth client per env (`photos-subscriber-dev/qa/prod`), and the JWT policy applied to **all three routes**, each validating only its own audience (client_id). Result matrix: own-env token → 200, wrong-env token → 403, no token → 401. A dev token is refused (403) by prod. Scripts: `register-subscribers.sh`, `deploy-phase4.sh` (now loops all routes), `test-oauth-isolation.sh`. Access kit: `api-access/` (Postman collection + curl, per-env creds). Real-world caveat: isolation ultimately depends on **secret custody** (prod secret not shared) + ideally a separate IdP/cluster for prod; our demo secrets are plaintext.

**Phase 4c — local rate limiting (throttling) (DONE — verified: burst of 300 → 266×200 then 34×429):** a kgateway `TrafficPolicy` with a **local token bucket** caps each Photos API route at **250 req/min** (`rateLimit.local.tokenBucket`: maxTokens 250, tokensPerFill 250, fillInterval 60s). Attached as a second TrafficPolicy on the route alongside the JWT policy (kgateway merges). Apply with `deploy-ratelimit.sh` (prints the live `rateLimit` schema + server-dry-runs before applying), verify with `test-ratelimit.sh` (bursts 300 requests → ~250×200 then 429). Manifest: `api/openchoreo/rate-limit.yaml`.
- **Local vs global:** *local* is enforced **per gateway replica** (effective cap = 250 × replicas) and needs no extra infra — good for basic protection. **Per-consumer / subscription-tier throttling** (WSO2-APIM-style Gold/Silver quotas keyed on the JWT `client_id`) requires **global** rate limiting = a `RateLimit` GatewayExtension pointing at an external Envoy ratelimit service + Redis-style store, which must be deployed separately (not part of this build).
- OpenChoreo has **no bundled WSO2-APIM equivalent** (no publisher/developer portal, self-service subscriptions, tiers, monetization, analytics). "APIM" here = gateway policies (enforce) + Thunder (identity) + Backstage (catalog). Apache APISIX is available as an ecosystem module if a richer gateway is wanted.

**Gotchas (all fixed):**
- Thunder `/applications` needs an admin token → get one as `openchoreo-system-app` **with `scope=system`** (plain token is `forbidden`).
- kgateway's go-jose parser rejects Thunder's JWKS `x5t`/`x5c` fields → reduce JWKS to `kty,kid,use,alg,n,e`.
- JWT config lives in a **`GatewayExtension`** (type JWT); the **`TrafficPolicy`** references it via `jwtAuth.extensionRef`; both go in the route's generated `dp-…` namespace.
- Enforcement is at the gateway — test through it (port-forward `svc/gateway-default -n openchoreo-data-plane 19080`), not via a pod port-forward.
- Bad policy config fails the route closed (500); check `trafficpolicy` status `Accepted=True` and `kgateway` controller logs.

## 10. Phase 6 — DEV/QA/PROD + autoscaling

**Part A+B done:** `qa` Environment + `authentic-photos-pipeline` (dev→qa→prod); Project repointed. The **same release** is bound to all three environments via ReleaseBindings, each overriding DB host/credentials and replica count. `verify-phase6.sh` confirms dev/qa/prod each report their own `APP_ENV` + `db:up`, prod at 2 replicas. Scripts: `deploy-phase6-envs.sh`, `promote-phase6.sh <qa|prod>`, `verify-phase6.sh`; manifests `openchoreo/environments/{qa,pipeline}.yaml`, `openchoreo/releasebindings/photos-api-{qa,prod}.yaml`.

**Gotcha:** per-env env-var overrides go under `spec.workloadOverrides.container.env` as a **list of `{key,value}`** (a map is silently dropped). `componentTypeEnvironmentConfigs.replicas/resources` work as a nested object.

**Part C (autoscaling) — pending run:** API has a demo `/alloc` endpoint; rebuild via CI, apply `api/openchoreo/hpa.yaml` (autoscaling/v2, memory 70% of 256Mi) with `deploy-hpa.sh`, drive it with `loadtest.sh`. Caveat: OpenChoreo's `renderedrelease-controller` manages replicas, so a hand-applied HPA may contend — the production-correct fix is a platform autoscaling Trait.

## 11. Phase 5 (planned)

- **Phase 5 — Web app + Thunder login.** Deploy the React app as `deployment/web-application`; wire OIDC authorization-code login to Thunder; browse + order end-to-end.
- **Phase 6 — DEV/QA/PROD + autoscaling.** Add a `qa` Environment + dev→qa→prod DeploymentPipeline; per-env `ReleaseBinding` configs (each API env → its env DB); attach an HPA on memory + a load test to show scaling; promote across environments.

---

## 9. Reference docs
- Docs home — https://openchoreo.dev/docs
- Developer abstractions — https://openchoreo.dev/docs/concepts/developer-abstractions/
- Platform abstractions — https://openchoreo.dev/docs/concepts/platform-abstractions/
- Creating a Project — https://openchoreo.dev/docs/developer-guide/projects-and-components/creating-a-project/
- Creating a Component — https://openchoreo.dev/docs/developer-guide/projects-and-components/creating-a-component/
- Examples catalog — https://openchoreo.dev/docs/getting-started/examples-catalog/
- k3d image import — https://k3d.io/stable/usage/commands/k3d_image_import/

---

# Appendix A — Quick command reference

```bash
# Cold start
~/restart-choreo.sh

# Phase 1 (repeat per env: dev|qa|prod)
bash apply-phase1.sh dev && bash verify-phase1.sh dev

# Phase 2
bash build-and-deploy-dev.sh && bash verify-phase2.sh

# Inspect what OpenChoreo created
kubectl get project authentic-photos -n default
kubectl get component,workload -n default
kubectl get pods -A | grep -E 'mysql|photos-api'
```

---

# Appendix B — Full file contents

> Everything below is the exact content of each file, so this playbook is self-sufficient.

## B.1  openchoreo/project.yaml
```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Project
metadata:
  name: authentic-photos
  namespace: default
  annotations:
    openchoreo.dev/display-name: "Authentic Photos"
    openchoreo.dev/description: "Online store selling licensed authentic photos: MySQL + subscribable OAuth API + web app"
spec:
  deploymentPipelineRef:
    kind: DeploymentPipeline
    name: default
```

## B.2  db/base/schema.sql
```sql
CREATE DATABASE IF NOT EXISTS authphotos
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE authphotos;

CREATE TABLE IF NOT EXISTS photos (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  title         VARCHAR(200)    NOT NULL,
  photographer  VARCHAR(150)    NOT NULL,
  description   TEXT            NULL,
  price_cents   INT UNSIGNED    NOT NULL,
  currency      CHAR(3)         NOT NULL DEFAULT 'USD',
  license_type  ENUM('standard','extended') NOT NULL DEFAULT 'standard',
  image_url     VARCHAR(500)    NOT NULL,
  is_active     BOOLEAN         NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_photos_active (is_active),
  KEY idx_photos_photographer (photographer)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS customers (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  external_subject VARCHAR(255)    NOT NULL,
  email            VARCHAR(255)    NULL,
  display_name     VARCHAR(200)    NULL,
  created_at       TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_customers_subject (external_subject)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS orders (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  customer_id  BIGINT UNSIGNED NOT NULL,
  photo_id     BIGINT UNSIGNED NOT NULL,
  amount_cents INT UNSIGNED    NOT NULL,
  currency     CHAR(3)         NOT NULL DEFAULT 'USD',
  status       ENUM('pending','paid','fulfilled','cancelled') NOT NULL DEFAULT 'pending',
  created_at   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_orders_customer (customer_id),
  KEY idx_orders_photo (photo_id),
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id),
  CONSTRAINT fk_orders_photo    FOREIGN KEY (photo_id)    REFERENCES photos(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS licenses (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id     BIGINT UNSIGNED NOT NULL,
  photo_id     BIGINT UNSIGNED NOT NULL,
  customer_id  BIGINT UNSIGNED NOT NULL,
  license_key  CHAR(36)        NOT NULL,
  license_type ENUM('standard','extended') NOT NULL,
  issued_at    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at   TIMESTAMP       NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_licenses_key (license_key),
  KEY idx_licenses_customer (customer_id),
  CONSTRAINT fk_licenses_order    FOREIGN KEY (order_id)    REFERENCES orders(id),
  CONSTRAINT fk_licenses_photo    FOREIGN KEY (photo_id)    REFERENCES photos(id),
  CONSTRAINT fk_licenses_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

## B.3  db/base/seed.sql
```sql
USE authphotos;

INSERT IGNORE INTO photos (id, title, photographer, description, price_cents, currency, license_type, image_url) VALUES
  (1, 'Dawn Over the Fjord',      'Ingrid Solberg',   'First light spilling across a Norwegian fjord.',   4900, 'USD', 'standard', 'https://picsum.photos/seed/fjord/1200/800'),
  (2, 'Market Spices, Marrakech', 'Youssef El Amrani','Pyramids of saffron and paprika in the medina.',  3900, 'USD', 'standard', 'https://picsum.photos/seed/spices/1200/800'),
  (3, 'Neon Rain, Tokyo',         'Kenji Nakamura',   'Shinjuku backstreets reflected in wet asphalt.',  6900, 'USD', 'extended', 'https://picsum.photos/seed/neon/1200/800'),
  (4, 'Salt Flats Mirror',        'Camila Rojas',     'Bolivia''s Salar de Uyuni after the rains.',      5900, 'USD', 'extended', 'https://picsum.photos/seed/saltflat/1200/800'),
  (5, 'Highland Cattle',          'Fiona MacLeod',    'A shaggy Highland cow in Scottish mist.',         2900, 'USD', 'standard', 'https://picsum.photos/seed/cattle/1200/800'),
  (6, 'Desert Dunes at Dusk',     'Omar Haddad',      'Wind-carved ridges in the Empty Quarter.',        4400, 'USD', 'standard', 'https://picsum.photos/seed/dunes/1200/800');

INSERT IGNORE INTO customers (id, external_subject, email, display_name) VALUES
  (1, 'demo-subject-0001', 'demo.buyer@example.com', 'Demo Buyer');
```

## B.4  db/base/kustomization.yaml
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - 30-service.yaml
  - 40-statefulset.yaml
configMapGenerator:
  - name: mysql-initdb
    files:
      - schema.sql
      - seed.sql
generatorOptions:
  disableNameSuffixHash: true
```

## B.5  db/base/30-service.yaml
```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
  labels:
    app: mysql
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
    - name: mysql
      port: 3306
      targetPort: 3306
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  labels:
    app: mysql
spec:
  selector:
    app: mysql
  ports:
    - name: mysql
      port: 3306
      targetPort: 3306
```

## B.6  db/base/40-statefulset.yaml
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: mysql:8.4
          # MySQL 8.4 removed --default-authentication-plugin; caching_sha2_password is default.
          ports:
            - name: mysql
              containerPort: 3306
          envFrom:
            - secretRef:
                name: mysql-credentials
          volumeMounts:
            - name: data
              mountPath: /var/lib/mysql
            - name: initdb
              mountPath: /docker-entrypoint-initdb.d
              readOnly: true
          resources:
            requests: { cpu: "100m", memory: "256Mi" }
            limits:   { cpu: "500m", memory: "512Mi" }
          readinessProbe:
            exec:
              command: ["bash","-c","mysqladmin ping -h127.0.0.1 -uroot -p\"$MYSQL_ROOT_PASSWORD\" --silent"]
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            exec:
              command: ["bash","-c","mysqladmin ping -h127.0.0.1 -uroot -p\"$MYSQL_ROOT_PASSWORD\" --silent"]
            initialDelaySeconds: 45
            periodSeconds: 20
            timeoutSeconds: 5
      volumes:
        - name: initdb
          configMap:
            name: mysql-initdb
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

## B.7  db/overlays/dev/kustomization.yaml  (qa/prod identical but for names/values)
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: authentic-photos-data-dev
resources:
  - namespace.yaml
  - ../../base
secretGenerator:
  - name: mysql-credentials
    literals:
      - MYSQL_ROOT_PASSWORD=dev-rootpw-change-me
      - MYSQL_DATABASE=authphotos
      - MYSQL_USER=authphotos_app
      - MYSQL_PASSWORD=dev-apppw-change-me
generatorOptions:
  disableNameSuffixHash: true
```
`db/overlays/dev/namespace.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: authentic-photos-data-dev
  labels:
    app.kubernetes.io/part-of: authentic-photos
    openchoreo.dev/environment: development
```
> `qa` overlay: namespace `authentic-photos-data-qa`, `qa-*` passwords, label `qa`.
> `prod` overlay: namespace `authentic-photos-data-prod`, `prod-*` passwords, label `production`, plus a patch bumping MySQL memory to 1Gi/512Mi and storage to 5Gi.

## B.8  api/package.json
```json
{
  "name": "authentic-photos-api",
  "version": "0.1.0",
  "description": "Authentic Photos API service (browse photos, order licensed copies)",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "ts-node src/index.ts"
  },
  "dependencies": {
    "express": "^4.19.2",
    "mysql2": "^3.11.0"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.14.0",
    "ts-node": "^10.9.2",
    "typescript": "^5.5.4"
  }
}
```

## B.9  api/tsconfig.json
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "moduleResolution": "node",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*.ts"]
}
```

## B.10  api/src/config.ts
```typescript
export const config = {
  port: parseInt(process.env.PORT ?? "8080", 10),
  db: {
    host: process.env.DB_HOST ?? "127.0.0.1",
    port: parseInt(process.env.DB_PORT ?? "3306", 10),
    user: process.env.DB_USER ?? "authphotos_app",
    password: process.env.DB_PASSWORD ?? "",
    database: process.env.DB_NAME ?? "authphotos",
  },
  environment: process.env.APP_ENV ?? "local",
};
```

## B.11  api/src/db.ts
```typescript
import mysql from "mysql2/promise";
import { config } from "./config";

export const pool = mysql.createPool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.database,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

export async function pingDb(): Promise<boolean> {
  const conn = await pool.getConnection();
  try {
    await conn.query("SELECT 1");
    return true;
  } finally {
    conn.release();
  }
}
```

## B.12  api/src/index.ts
```typescript
import express, { Request, Response } from "express";
import { RowDataPacket } from "mysql2";
import { pool, pingDb } from "./db";
import { config } from "./config";

const app = express();
app.use(express.json());

function toPhoto(row: RowDataPacket) {
  return {
    id: row.id,
    title: row.title,
    photographer: row.photographer,
    description: row.description,
    price: { amount: row.price_cents / 100, currency: row.currency },
    licenseType: row.license_type,
    imageUrl: row.image_url,
  };
}

app.get("/health", async (_req: Request, res: Response) => {
  try {
    await pingDb();
    res.json({ status: "ok", environment: config.environment, db: "up" });
  } catch {
    res.status(503).json({ status: "degraded", environment: config.environment, db: "down" });
  }
});

app.get("/photos", async (_req: Request, res: Response) => {
  try {
    const [rows] = await pool.query<RowDataPacket[]>(
      "SELECT id, title, photographer, description, price_cents, currency, license_type, image_url " +
        "FROM photos WHERE is_active = TRUE ORDER BY id"
    );
    res.json({ count: rows.length, photos: rows.map(toPhoto) });
  } catch (err) {
    console.error("GET /photos failed:", err);
    res.status(500).json({ error: "internal_error" });
  }
});

app.get("/photos/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ error: "invalid_id" });
  try {
    const [rows] = await pool.query<RowDataPacket[]>(
      "SELECT id, title, photographer, description, price_cents, currency, license_type, image_url " +
        "FROM photos WHERE id = ? AND is_active = TRUE",
      [id]
    );
    if (rows.length === 0) return res.status(404).json({ error: "not_found" });
    res.json(toPhoto(rows[0]));
  } catch (err) {
    console.error("GET /photos/:id failed:", err);
    res.status(500).json({ error: "internal_error" });
  }
});

app.listen(config.port, () => {
  console.log(`Authentic Photos API listening on :${config.port} (env=${config.environment})`);
});
```

## B.13  api/Dockerfile
```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
USER node
EXPOSE 8080
CMD ["node", "dist/index.js"]
```

## B.14  api/.dockerignore
```
node_modules
dist
npm-debug.log
.git
.env
```

## B.15  api/openchoreo/component.yaml
```yaml
apiVersion: openchoreo.dev/v1alpha1
kind: Component
metadata:
  name: photos-api
  namespace: default
  annotations:
    openchoreo.dev/display-name: "Photos API"
    openchoreo.dev/description: "Browse photos and order licensed copies"
spec:
  owner:
    projectName: authentic-photos
  componentType:
    kind: ClusterComponentType
    name: deployment/service
  autoDeploy: true
---
apiVersion: openchoreo.dev/v1alpha1
kind: Workload
metadata:
  name: photos-api-workload
  namespace: default
spec:
  owner:
    projectName: authentic-photos
    componentName: photos-api
  container:
    image: "authentic-photos/photos-api:0.1.0"
    env:
      - key: PORT
        value: "8080"
      - key: APP_ENV
        value: "development"
      - key: DB_HOST
        value: "mysql.authentic-photos-data-dev.svc.cluster.local"
      - key: DB_PORT
        value: "3306"
      - key: DB_NAME
        value: "authphotos"
      - key: DB_USER
        value: "authphotos_app"
      - key: DB_PASSWORD
        value: "dev-apppw-change-me"
  endpoints:
    api:
      type: HTTP
      port: 8080
      visibility: [external]
```

## B.16  api/openchoreo/netpol-db-allow-dev.yaml
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-mysql-ingress
  namespace: authentic-photos-data-dev
spec:
  podSelector:
    matchLabels:
      app: mysql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 3306
```

## B.17  Scripts (apply-phase1.sh, verify-phase1.sh, build-and-deploy-dev.sh, verify-phase2.sh)
These live in the repo root and are reproduced in `PHASE1.md` / `PHASE2.md`. Key one-liners:
```bash
# apply-phase1.sh <env>: kubectl apply project.yaml ; kubectl apply -k db/overlays/<env> ; rollout status
# verify-phase1.sh <env>: SHOW TABLES + SELECT photos via kubectl exec
# build-and-deploy-dev.sh: docker build ; k3d image import <tag> -c openchoreo ; kubectl apply component.yaml
# verify-phase2.sh: find pod, port-forward 18080->8080, curl /health /photos /photos/3
```

---

*End of Playbook. Phases 3–6 will be appended here as we build them.*
