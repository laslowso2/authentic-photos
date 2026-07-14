# Calling the Authentic Photos API from your Mac (Postman / curl)

The API is exposed through OpenChoreo's data-plane gateway, which routes by **hostname** — every
request must carry the right `Host` header. After the Phase 4b hardening, **every environment
requires a token, and each environment only accepts its own environment's token.**

## Endpoints + credentials (per environment)
| Env | Host header | OAuth client | Secret |
|-----|-------------|--------------|--------|
| dev  | `development-default.openchoreoapis.localhost` | `photos-subscriber-dev`  | `photos-subscriber-dev-secret` |
| qa   | `qa-default.openchoreoapis.localhost`          | `photos-subscriber-qa`   | `photos-subscriber-qa-secret` |
| prod | `production-default.openchoreoapis.localhost`  | `photos-subscriber-prod` | `photos-subscriber-prod-secret` |

Path for all: `/photos-api-api/photos`. Confirm hostnames anytime with `kubectl get httproute -A`.

> Isolation: a token from `photos-subscriber-dev` is **rejected (401) by qa and prod** — each
> gateway policy validates only its own environment's audience (the client_id). In real use the
> **prod** secret is custody-controlled and never shared with dev/qa people.

## Step 0 — make the gateway reachable at localhost:19080
```bash
kubectl port-forward -n openchoreo-data-plane svc/gateway-default 19080:19080   # keep running
```

## curl (per environment)
```bash
# pick an env's client:
CID=photos-subscriber-dev; SEC=photos-subscriber-dev-secret          # or -qa / -prod
HOST=development-default.openchoreoapis.localhost                     # match the env

TOKEN=$(curl -s -u "$CID:$SEC" -d grant_type=client_credentials \
  http://thunder.openchoreo.localhost:8080/oauth2/token | sed 's/.*"access_token":"//;s/".*//')

curl -H "Host: $HOST" -H "Authorization: Bearer $TOKEN" \
     http://localhost:19080/photos-api-api/photos            # 200 with the RIGHT env token

# Prove isolation: dev token against prod -> 401
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Host: production-default.openchoreoapis.localhost" \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:19080/photos-api-api/photos               # 401
```

## Postman
1. Import `authentic-photos-api.postman_collection.json`.
2. Under **Tokens**, run the token request for the env(s) you want — each stores its own variable
   (`token_dev`, `token_qa`, `token_prod`).
3. Run **DEV/QA/PROD /photos** — each uses its matching token and `Host` header.
4. Run **"PROD with DEV token (expect 401)"** to see isolation in action.

Notes: Postman will send the custom `Host` header (a warning is normal). `thunder.openchoreo.localhost`
resolves on your Mac already. If `localhost:19080` refuses, keep the port-forward from Step 0 running.
