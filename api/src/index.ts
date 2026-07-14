import express, { Request, Response } from "express";
import { RowDataPacket, ResultSetHeader } from "mysql2";
import { randomUUID } from "crypto";
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

// Identify the caller from the gateway-validated Bearer JWT.
// The gateway already verified the signature/issuer/audience, so here we only DECODE
// the claims to know WHO is calling (never trust this for auth on an unprotected path).
type User = { subject: string; email?: string; name?: string };
function getUser(req: Request): User | null {
  const h = (req.headers.authorization as string) || "";
  const m = h.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  try {
    const part = m[1].split(".")[1];
    const json = Buffer.from(part.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8");
    const c = JSON.parse(json);
    const subject = c.sub || c.username || c.client_id;
    if (!subject) return null;
    return { subject, email: c.email, name: c.name || c.given_name || c.preferred_username };
  } catch {
    return null;
  }
}

// Find-or-create the customer row for this identity; returns its id.
async function ensureCustomer(u: User): Promise<number> {
  const [rows] = await pool.query<RowDataPacket[]>(
    "SELECT id FROM customers WHERE external_subject = ?",
    [u.subject]
  );
  if (rows.length) return rows[0].id;
  const [res] = await pool.query<ResultSetHeader>(
    "INSERT INTO customers (external_subject, email, display_name) VALUES (?, ?, ?)",
    [u.subject, u.email ?? null, u.name ?? null]
  );
  return res.insertId;
}

app.get("/health", async (_req: Request, res: Response) => {
  try {
    await pingDb();
    res.json({ status: "ok", environment: config.environment, db: "up" });
  } catch {
    res.status(503).json({ status: "degraded", environment: config.environment, db: "down" });
  }
});

// Who am I? (echoes the identity the gateway forwarded)
app.get("/me", (req: Request, res: Response) => {
  const u = getUser(req);
  if (!u) return res.status(401).json({ error: "no_identity" });
  res.json({ subject: u.subject, email: u.email ?? null, name: u.name ?? null });
});

// Browse the catalogue.
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

app.get("/photos/:id", async (req: Request, res: Response) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) return res.status(400).json({ error: "invalid_id" });
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

// Order a licensed copy of a photo. Body: { photoId }.
// For the demo we fulfil immediately: create the order (paid) and issue a license.
app.post("/orders", async (req: Request, res: Response) => {
  const u = getUser(req);
  if (!u) return res.status(401).json({ error: "no_identity" });
  const photoId = Number(req.body?.photoId);
  if (!Number.isInteger(photoId) || photoId <= 0) return res.status(400).json({ error: "invalid_photoId" });

  const conn = await pool.getConnection();
  try {
    const [prows] = await conn.query<RowDataPacket[]>(
      "SELECT id, price_cents, currency, license_type FROM photos WHERE id = ? AND is_active = TRUE",
      [photoId]
    );
    if (prows.length === 0) return res.status(404).json({ error: "photo_not_found" });
    const photo = prows[0];

    await conn.beginTransaction();
    const customerId = await ensureCustomer(u);
    const [ores] = await conn.query<ResultSetHeader>(
      "INSERT INTO orders (customer_id, photo_id, amount_cents, currency, status) VALUES (?, ?, ?, ?, 'fulfilled')",
      [customerId, photoId, photo.price_cents, photo.currency]
    );
    const orderId = ores.insertId;
    const licenseKey = randomUUID();
    await conn.query(
      "INSERT INTO licenses (order_id, photo_id, customer_id, license_key, license_type) VALUES (?, ?, ?, ?, ?)",
      [orderId, photoId, customerId, licenseKey, photo.license_type]
    );
    await conn.commit();

    res.status(201).json({
      orderId,
      status: "fulfilled",
      photoId,
      amount: { amount: photo.price_cents / 100, currency: photo.currency },
      license: { key: licenseKey, type: photo.license_type },
    });
  } catch (err) {
    await conn.rollback().catch(() => {});
    console.error("POST /orders failed:", err);
    res.status(500).json({ error: "internal_error" });
  } finally {
    conn.release();
  }
});

// List the current user's orders + licenses.
app.get("/orders", async (req: Request, res: Response) => {
  const u = getUser(req);
  if (!u) return res.status(401).json({ error: "no_identity" });
  try {
    const [rows] = await pool.query<RowDataPacket[]>(
      "SELECT o.id AS order_id, o.status, o.amount_cents, o.currency, o.created_at, " +
        "p.id AS photo_id, p.title, p.image_url, l.license_key, l.license_type " +
        "FROM orders o JOIN customers c ON c.id = o.customer_id " +
        "JOIN photos p ON p.id = o.photo_id LEFT JOIN licenses l ON l.order_id = o.id " +
        "WHERE c.external_subject = ? ORDER BY o.created_at DESC",
      [u.subject]
    );
    res.json({
      count: rows.length,
      orders: rows.map((r) => ({
        orderId: r.order_id,
        status: r.status,
        amount: { amount: r.amount_cents / 100, currency: r.currency },
        photo: { id: r.photo_id, title: r.title, imageUrl: r.image_url },
        license: r.license_key ? { key: r.license_key, type: r.license_type } : null,
        createdAt: r.created_at,
      })),
    });
  } catch (err) {
    console.error("GET /orders failed:", err);
    res.status(500).json({ error: "internal_error" });
  }
});

// Demo-only: hold N MB of memory for S seconds to trigger memory-based autoscaling.
const held: Record<string, Buffer> = {};
app.get("/alloc", (req: Request, res: Response) => {
  const mb = Math.min(Math.max(Number(req.query.mb ?? 100), 1), 400);
  const secs = Math.min(Math.max(Number(req.query.secs ?? 30), 1), 180);
  const key = `${Date.now()}-${Math.random()}`;
  held[key] = Buffer.alloc(mb * 1024 * 1024, 1);
  setTimeout(() => { delete held[key]; }, secs * 1000);
  res.json({ allocatedMB: mb, heldSeconds: secs, environment: config.environment });
});

app.listen(config.port, () => {
  console.log(`Authentic Photos API listening on :${config.port} (env=${config.environment})`);
});
