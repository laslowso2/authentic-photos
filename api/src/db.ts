import mysql from "mysql2/promise";
import { config } from "./config";

// A connection pool: reuses TCP connections instead of opening one per request.
export const pool = mysql.createPool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.database,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// Simple connectivity check used by the /health endpoint.
export async function pingDb(): Promise<boolean> {
  const conn = await pool.getConnection();
  try {
    await conn.query("SELECT 1");
    return true;
  } finally {
    conn.release();
  }
}
