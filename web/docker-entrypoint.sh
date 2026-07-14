#!/bin/sh
# Regenerate /config.js from env vars at container start, so the SAME image works in any
# environment (Thunder URL, client_id, API base, redirect all injected per-env).
set -e
cat > /usr/share/nginx/html/config.js <<EOF
window.__APP_CONFIG__ = {
  thunderUrl: "${WEB_THUNDER_URL:-http://thunder.openchoreo.localhost:8080}",
  clientId: "${WEB_CLIENT_ID:-authentic-photos-web}",
  redirectUri: "${WEB_REDIRECT_URI:-}",
  apiBase: "${WEB_API_BASE:-}"
};
EOF
echo "config.js written:"; cat /usr/share/nginx/html/config.js
