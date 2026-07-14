import React from "react";
import { createRoot } from "react-dom/client";
import { userManager } from "./auth";
import App from "./App";
import "./styles.css";

async function boot() {
  // Handle the OIDC redirect callback, then clean the URL.
  if (window.location.pathname === "/callback") {
    try {
      await userManager.signinRedirectCallback();
    } catch (e) {
      console.error("OIDC callback failed:", e);
    }
    window.history.replaceState({}, "", "/");
  }
  createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
}

boot();
