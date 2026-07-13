// All configuration comes from environment variables.
// In OpenChoreo these are injected per-environment via the Workload / ReleaseBinding,
// so the SAME image runs unchanged in dev, qa, and prod.
export const config = {
  port: parseInt(process.env.PORT ?? "8080", 10),
  db: {
    host: process.env.DB_HOST ?? "127.0.0.1",
    port: parseInt(process.env.DB_PORT ?? "3306", 10),
    user: process.env.DB_USER ?? "authphotos_app",
    password: process.env.DB_PASSWORD ?? "",
    database: process.env.DB_NAME ?? "authphotos",
  },
  // Purely cosmetic: lets us prove which environment answered a request.
  environment: process.env.APP_ENV ?? "local",
};
