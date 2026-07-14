# Phase 4 — Publish API + OAuth Subscription

**Goal:** let *other applications* subscribe to the Photos API and call it with OAuth, so the API is protected at the gateway — no token, no access.

**Exit criteria (met):** `GET /photos` through the gateway returns **401 without a token** and **200 + 6 photos with a valid Thunder token**.

---

## How it works on this platform

This OpenChoreo install has **no built-in "API subscription" feature** (Phase 0 confirmed: only kgateway + Gateway API, no subscription CRD). So we assemble the OAuth story from two real primitives:

```
External app --(client_id/secret)--> Thunder /oauth2/token --(JWT)-->
     app --(Authorization: Bearer JWT)--> kgateway --(validate: issuer+audience+signature via JWKS)--> Photos API
```

- **Thunder** is the OAuth server. Each subscriber is a `client_credentials` **application** in Thunder; it exchanges its client_id/secret for a signed JWT.
- **kgateway** enforces the token at the API's route: a **GatewayExtension** (type `JWT`) holds Thunder's issuer + audience + signing keys, and a **TrafficPolicy** attaches that check to the route. Invalid/missing token → 401 at the gateway, the request never reaches the API.

"Subscribing" = registering a client in Thunder and adding its client_id to the API's allowed audiences.

---

## What we built
| File | Purpose |
|---|---|
| `api/openchoreo/thunder-subscriber-app.json` | The subscriber app definition (client_credentials) |
| `register-subscriber.sh` | Registers it in Thunder (auth'd as the System App with `scope=system`) |
| `get-token.sh` | Acts as the subscriber: gets a JWT and decodes its claims |
| `api/openchoreo/gateway-jwt.yaml` | `GatewayExtension` (JWT provider) + `TrafficPolicy` (enforce on route) |
| `deploy-phase4.sh` | Fetches Thunder JWKS, cleans it, renders + applies the policy to the route |
| `test-phase4.sh` | Proves 401 without token / 200 with token, through the gateway |

## Run it
```bash
# 1. Register the external subscriber app in Thunder
bash ~/Documents/Claude/OpenChoreo/authentic-photos/register-subscriber.sh

# 2. (optional) See a real token + its claims
bash ~/Documents/Claude/OpenChoreo/authentic-photos/get-token.sh

# 3. Protect the API route with JWT validation
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-phase4.sh

# 4. Prove it
bash ~/Documents/Claude/OpenChoreo/authentic-photos/test-phase4.sh
```

## How an external subscriber calls the API
```bash
# get a token
TOKEN=$(curl -s -u photos-subscriber:photos-subscriber-secret \
  -d grant_type=client_credentials \
  http://thunder.openchoreo.localhost:8080/oauth2/token | ... access_token)

# call the API through the gateway (Host header = the route hostname)
curl -H "Host: development-default.openchoreoapis.localhost" \
     -H "Authorization: Bearer $TOKEN" \
     http://<gateway>/photos-api-api/photos
```

## Adding another subscriber
1. Copy `thunder-subscriber-app.json`, change `name` + `client_id` + `client_secret`, register it.
2. Add the new `client_id` to `audiences` in `api/openchoreo/gateway-jwt.yaml`, re-run `deploy-phase4.sh`.

---

## Gotchas we hit (all fixed — worth knowing)
1. **Thunder `/applications` requires an admin token.** The bootstrap scripts run privileged; in steady state you must authenticate. Get a token **as the System App (`openchoreo-system-app`) with `scope=system`** and pass it as `Bearer`. Without `scope=system` the token is `forbidden`.
2. **kgateway's JWKS parser (go-jose) rejects Thunder's JWKS as-is** — the `x5t`/`x5c` X.509 fields cause `"x5t header has invalid encoding"`. Fix: reduce the JWKS to `kty,kid,use,alg,n,e` only (deploy-phase4.sh does this).
3. **JWT config lives in a `GatewayExtension`**, not inline in the TrafficPolicy — `TrafficPolicy.jwtAuth.extensionRef` points to it. Both must be in the **route's** namespace (the generated `dp-…` one).
4. **Test through the gateway, not a pod port-forward** — JWT is enforced at the gateway; port-forwarding the pod bypasses it.
5. **Config errors fail the route closed** (HTTP 500 "invalid route configuration"). Check `kubectl get trafficpolicy <name> -n <ns> -o jsonpath='{.status.ancestors[0].conditions}'` for `Accepted=True`, and the kgateway controller logs (`openchoreo-control-plane/kgateway-*`) for the real reason.

---

## Reference docs
- kgateway TrafficPolicy / GatewayExtension (JWT) — https://kgateway.dev/docs/
- OpenChoreo runtime model (cells, gateways) — https://openchoreo.dev/docs/concepts/runtime-model/
- OIDC client credentials — https://datatracker.ietf.org/doc/html/rfc6749#section-4.4

## Next
- **Phase 5** — React web app + user login via Thunder (OIDC authorization-code).
- **Phase 6** — DEV/QA/PROD environments + promotion + memory-based autoscaling.
