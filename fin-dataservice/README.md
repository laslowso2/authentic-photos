# Financial DataService (Ballerina) + `findw` warehouse

A **Ballerina** service exposing a REST reporting API over a financial **data warehouse** (`findw`),
built on OpenChoreo with the **native Ballerina buildpack**. This also serves as a live proof of the
AAA migration pattern *WSO2 DataService → Ballerina*.

## Pieces
- **`findw/schema-findw.sql` + `findw/seed-findw.sql`** — a star schema (`dim_date`, `dim_photo`, `fact_sales`) in a separate `findw` database in the same MySQL instance, seeded with ~12 months / 500 synthetic sales (~$27k revenue).
- **`fin-dataservice/`** — the Ballerina package: `Ballerina.toml`, `service.bal` (HTTP service + `ballerinax/mysql`), `workload.yaml` (endpoint + DB env), `openchoreo/` (Component using `ballerina-buildpack-builder`).

## Report endpoints (`/reports/...`)
| Endpoint | Report |
|---|---|
| `GET /reports/health` | liveness |
| `GET /reports/summary` | total revenue, sales, customers, avg order value |
| `GET /reports/revenueByMonth` | monthly revenue trend |
| `GET /reports/topPhotos` | best-selling photos by revenue |
| `GET /reports/revenueByLicense` | revenue split by license type |

## Run it
```bash
# 1. Create + seed the warehouse in the dev MySQL
bash ~/Documents/Claude/OpenChoreo/authentic-photos/apply-findw.sh dev

# 2. Push and deploy the Ballerina service (built by the Ballerina buildpack)
git -C ~/Documents/Claude/OpenChoreo/authentic-photos add -A
git -C ~/Documents/Claude/OpenChoreo/authentic-photos commit -m "Ballerina financial DataService + findw warehouse"
git -C ~/Documents/Claude/OpenChoreo/authentic-photos push
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-fin.sh https://github.com/laslowso2/authentic-photos

# 3. Watch the build (first Ballerina buildpack build can be slow)
kubectl get workflowrun -n default -w

# 4. Once deployed, test the reports (open / no auth yet)
bash ~/Documents/Claude/OpenChoreo/authentic-photos/test-fin.sh
```

## Honest caveats
- I can't compile Ballerina in my sandbox, so `service.bal` may need a **compile iteration** (the build logs will tell us) — most likely candidates: the `ballerinax/mysql` client init args, the query-stream iteration, or the `Ballerina.toml` `distribution` version vs the buildpack's Ballerina version.
- The **Ballerina buildpack** workflow params here are minimal (`repository` only); if the build reports missing parameters, we add them (same discover-from-the-build-error approach we used for the Docker builder).
- **MySQL SSL:** if the connection fails on TLS, we add `mysql:Options` with SSL disabled/preferred.
- The service is **open** (no OAuth) per your choice; we add the per-env JWT policy when the finance app is built.
- Warehouse seeded in **dev** only; re-run `apply-findw.sh qa|prod` when needed.
