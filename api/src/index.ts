import express, { Request, Response } from "express";
import { RowDataPacket } from "mysql2";
import { pool, pingDb } from "./db";
import { config } from "./config";

const app = express();
app.use(express.json());

// Shape a DB row into a clean API object (money as dollars, not raw cents).
function toPhoto(row: RowDataPacket) {
  return {
    id: row.id,
    title: row.title,
    photographer: row.photographer,
    description: row.description,
    price: { amount: row.price_cents / 100, currency: row.currency },
    licenseType: row.license_type,
    imageUrl: row.image_url,
  };
}

// Liveness/readiness: reports whether the DB is reachable.
app.get("/health", async (_req: Request, res: Response) => {
  try {
    await pingDb();
    res.json({ status: "ok", environment: config.environment, db: "up" });
  } catch {
    res.status(503).json({ status: "degraded", environment: config.environment, db: "down" });
  }
});

// Browse the catalogue of photos available for licensing.
app.get("/photos", async (_req: Request, res: Response) => {
  try {
    const [rows] = await pool.query<RowDataPacket[]>(
      "SELECT id, title, photographer, description, price_cents, currency, license_type, image_url " +
        "FROM photos WHERE is_active = TRUE ORDER BY id"
    );
    res.json({ count: rows.length, photos: rows.map(toPhoto) });
  } catch (err) {
    console.error("GET /photos failed:", err);
    res.status(500).json({ error: "internal_error" });
  }
});

// Fetch a single photo by id.
app.get("/photos/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return res.status(400).json({ error: "invalid_id" });
  }
  try {
    const [rows] = await pool.query<RowDataPacket[]>(
      "SELECT id, title, photographer, description, price_cents, currency, license_type, image_url " +
        "FROM photos WHERE id = ? AND is_active = TRUE",
      [id]
    );
    if (rows.length === 0) return res.status(404).json({ error: "not_found" });
    res.json(toPhoto(rows[0]));
  } catch (err) {
    console.error("GET /photos/:id failed:", err);
    res.status(500).json({ error: "internal_error" });
  }
});

app.listen(config.port, () => {
  console.log(`Authentic Photos API listening on :${config.port} (env=${config.environment})`);
});
