import { useEffect, useState } from "react";
import type { User } from "oidc-client-ts";
import { userManager, login, logout } from "./auth";
import { getPhotos, getMyOrders, orderPhoto } from "./api";

type Photo = { id: number; title: string; photographer: string; imageUrl: string;
  price: { amount: number; currency: string }; licenseType: string };
type Order = { orderId: number; photo: { title: string }; license: { key: string; type: string } | null };

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [msg, setMsg] = useState("");

  useEffect(() => { userManager.getUser().then(setUser); }, []);
  useEffect(() => { if (user) refresh(); }, [user]);

  async function refresh() {
    try {
      const p = await getPhotos(); setPhotos(p.photos);
      const o = await getMyOrders(); setOrders(o.orders);
    } catch (e: any) { setMsg(String(e.message || e)); }
  }
  async function buy(id: number) {
    setMsg("");
    try {
      const r = await orderPhoto(id);
      setMsg(`License issued: ${r.license.key}`);
      const o = await getMyOrders(); setOrders(o.orders);
    } catch (e: any) { setMsg(String(e.message || e)); }
  }

  if (!user) {
    return (
      <div className="center">
        <h1>Authentic Photos</h1>
        <p className="mut">Licensed authentic photography.</p>
        <button className="primary" onClick={() => login()}>Log in with Thunder</button>
      </div>
    );
  }

  const p = user.profile as any;
  const name = p.name || p.email || p.preferred_username || p.sub;
  return (
    <div className="app">
      <header>
        <h1>Authentic Photos</h1>
        <div className="who">Signed in as <b>{name}</b> <button onClick={() => logout()}>Log out</button></div>
      </header>

      {msg && <div className="msg">{msg}</div>}

      <h2>Catalogue</h2>
      <div className="grid">
        {photos.map((ph) => (
          <div className="card" key={ph.id}>
            <img src={ph.imageUrl} alt={ph.title} />
            <div className="body">
              <b>{ph.title}</b>
              <div className="mut">{ph.photographer}</div>
              <div className="price">${ph.price.amount} · {ph.licenseType}</div>
              <button className="primary" onClick={() => buy(ph.id)}>Order license</button>
            </div>
          </div>
        ))}
      </div>

      <h2>My licenses</h2>
      {orders.length === 0 ? <p className="mut">No licenses yet.</p> : (
        <ul className="orders">
          {orders.map((o) => (
            <li key={o.orderId}>
              <b>{o.photo.title}</b> — <code>{o.license?.key}</code> <span className="mut">({o.license?.type})</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
