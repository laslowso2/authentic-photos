import { config } from "./config";
import { userManager } from "./auth";

// Call the Photos API with the logged-in user's access token (Bearer).
async function authFetch(path: string, init: RequestInit = {}) {
  const user = await userManager.getUser();
  const token = user?.access_token;
  const res = await fetch(config.apiBase + path, {
    ...init,
    headers: {
      ...(init.headers || {}),
      Authorization: token ? `Bearer ${token}` : "",
      "Content-Type": "application/json",
    },
  });
  if (!res.ok) throw new Error(`${res.status}: ${await res.text()}`);
  return res.json();
}

export const getPhotos = () => authFetch("/photos");
export const getMyOrders = () => authFetch("/orders");
export const orderPhoto = (photoId: number) =>
  authFetch("/orders", { method: "POST", body: JSON.stringify({ photoId }) });
