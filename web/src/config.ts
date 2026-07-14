// Reads the runtime config injected by /config.js (window.__APP_CONFIG__).
declare global {
  interface Window {
    __APP_CONFIG__?: {
      thunderUrl?: string;
      clientId?: string;
      redirectUri?: string;
      apiBase?: string;
    };
  }
}

const c = window.__APP_CONFIG__ || {};
export const config = {
  thunderUrl: c.thunderUrl || "http://thunder.openchoreo.localhost:8080",
  clientId: c.clientId || "authentic-photos-web",
  redirectUri: c.redirectUri || window.location.origin + "/callback",
  apiBase: c.apiBase || "",
};
