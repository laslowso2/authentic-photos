import { UserManager, User, WebStorageStateStore } from "oidc-client-ts";
import { config } from "./config";

// OIDC Authorization Code + PKCE against Thunder (public client, no secret).
export const userManager = new UserManager({
  authority: config.thunderUrl, // uses ${authority}/.well-known/openid-configuration
  client_id: config.clientId,
  redirect_uri: config.redirectUri,
  response_type: "code",
  scope: "openid profile email",
  post_logout_redirect_uri: window.location.origin,
  loadUserInfo: false, // read name/email from the id_token claims instead of calling /userinfo
  userStore: new WebStorageStateStore({ store: window.localStorage }),
});

export const getUser = (): Promise<User | null> => userManager.getUser();
export const login = () => userManager.signinRedirect();
export const logout = () => userManager.signoutRedirect();
