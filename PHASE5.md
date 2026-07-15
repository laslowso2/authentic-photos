# Phase 5 — Web App + User Login (Thunder OIDC)

**Goal:** a React web app where a customer **logs in via Thunder** (OIDC Authorization Code + PKCE), **browses** photos, and **orders** a licensed copy — the customer-facing side of the store.

**Architecture (chosen):** pure **React SPA** (public client, PKCE, no secret) deployed as an OpenChoreo `deployment/web-application`. The SPA gets a **user** token from Thunder and calls the Photos API directly. Two gateway tweaks make that work: the web-app's `client_id` is added to the API's allowed JWT **audiences**, and **CORS** is enabled on the API route. (A BFF would be more production-secure; we chose SPA-direct for a clean demo.)

```
User → SPA (login: Thunder /oauth2/authorize, PKCE) → user JWT
     → SPA calls API with Bearer user-JWT → gateway validates (issuer + audience incl. web-app client_id) → API
```

## Stages
1. **API order endpoints (this stage):** `POST /orders` (issue a license), `GET /orders`, `GET /me`. The API identifies the user from the gateway-validated JWT (`sub`/`email`), find-or-creates a customer, creates the order, and issues a license (UUID). Rebuilt via the CI pipeline.
2. **React SPA:** Vite + React; Thunder OIDC PKCE login; browse photos; order → show license. Runtime config (Thunder URL, client_id, API base) injected at deploy. Deployed as a `web-application` component.
3. **Thunder OIDC client + gateway wiring:** register the SPA as a PKCE public client in Thunder (redirect URIs = the deployed web-app URL); add the web-app `client_id` to the API JWT audiences; add a CORS `TrafficPolicy` on the API route.
4. **End-to-end browser test:** log in, browse, order, receive a license.

---

## Stage 1 — run it
The API now has `GET /me`, `POST /orders`, `GET /orders` (source in `api/src/index.ts`, typecheck verified). Ship it through CI, then smoke-test:

```bash
# rebuild the API from source (new endpoints) and redeploy dev
git -C ~/Documents/Claude/OpenChoreo/authentic-photos commit -am "Phase 5: API order/license endpoints"
git -C ~/Documents/Claude/OpenChoreo/authentic-photos push
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-phase3.sh https://github.com/laslowso2/authentic-photos
#   wait for the build:  bash verify-phase3.sh   (pod image flips to a new v1-... tag)

# smoke-test the order flow through the gateway
bash ~/Documents/Claude/OpenChoreo/authentic-photos/test-orders.sh
```
Success: `/me` echoes the subject, `POST /orders` returns an `orderId` + a `license.key` (UUID), and `GET /orders` lists it.

*(The smoke test uses a dev client-credentials token, so the "customer" is `photos-subscriber-dev`. Real users arrive via the SPA in Stage 2–4.)*

---

## What's next after Stage 1
Once orders work via curl, Stage 2 builds the React SPA, Stage 3 registers the Thunder client + does the gateway audience/CORS wiring (needs the web-app's deployed URL first), and Stage 4 is the browser walkthrough.

## Notes / things to know
- **Token in the browser** (SPA-direct) is acceptable for this demo; a BFF is the production-grade choice.
- **CORS** will be handled at the gateway (kgateway `TrafficPolicy.cors`), not in the API, to avoid duplicate headers.
- **Users:** we can log in with the Thunder users from bootstrap (e.g. `admin@openchoreo.dev` / `Admin@123`) unless we enable self-registration.
- **Redirect URI chicken-and-egg:** the web app must be deployed first to learn its URL, then the Thunder client is registered with that redirect — hence Stage 2 before Stage 3.

---

## Stage 3 — wire login + gateway (run it)
Web app URL (dev): `http://web-photos-web-development-default-47d2cd39.openchoreoapis.localhost:19080`

```bash
# 1. Register the web app as a Thunder OIDC PKCE client (redirect = <web-url>/callback, auto-discovered)
bash ~/Documents/Claude/OpenChoreo/authentic-photos/register-web-client.sh

# 2. Re-apply the JWT policy so the API also accepts the web app's user tokens (audience authentic-photos-web)
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-phase4.sh

# 3. Allow the browser (web origin) to call the API cross-origin
bash ~/Documents/Claude/OpenChoreo/authentic-photos/deploy-cors.sh
```

```bash
# 4. Let your Mac resolve the hostnames (browser needs these). thunder line may already exist.
sudo sh -c 'cat >> /etc/hosts <<EOF
127.0.0.1 web-photos-web-development-default-47d2cd39.openchoreoapis.localhost
127.0.0.1 development-default.openchoreoapis.localhost
127.0.0.1 thunder.openchoreo.localhost
EOF'
```

## Stage 4 — try it in the browser
Open: **http://web-photos-web-development-default-47d2cd39.openchoreoapis.localhost:19080**
1. Click **Log in with Thunder** → Thunder login page → sign in as `admin@openchoreo.dev` / `Admin@123`.
2. You're redirected back; the catalogue loads (API call with your user token).
3. Click **Order license** on a photo → a license (UUID) is issued and appears under **My licenses**.

### Troubleshooting (browser console is your friend — open DevTools)
- **CORS error on the call to `thunder.../oauth2/token`**: Thunder must allow the web origin. Its `cors.allowed_origins` doesn't include it by default — paste the exact console error and I'll patch Thunder's config + restart it (kept reactive since Thunder may auto-allow the registered redirect origin).
- **API calls return 403**: the web audience didn't attach — re-run `deploy-phase4.sh` and check `kubectl get trafficpolicy -A | grep photos-api`.
- **API calls blocked by CORS**: `deploy-cors.sh` didn't apply (schema mismatch) — send me its output.
- **`redirect_uri` mismatch at Thunder**: the registered redirect must exactly equal `<web-origin>/callback` — re-run `register-web-client.sh` (it derives it from the live route).
- **Photos load but empty / 401**: token not forwarded — confirm the JWT policy has `forwardToken: true` (added in Stage 1).
