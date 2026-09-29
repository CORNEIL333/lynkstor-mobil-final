// Seed + smoke for the admin dashboard browser check. Creates ONE ephemeral
// demo business (via the real /register flow using a generated code) plus a
// commercial staff + field_activities so every dashboard tab has data. The
// login admin itself is seeded by tool/seed_e2e_demo.ps1 (id b000...0001).
// All created rows use the biz-e2e- prefix → removed by purge_neon_demo.sql;
// the generated code is orphaned→void or →used so the purge's step 3b removes it.
const BASE = (process.env.E2E_BASE || "https://br-curly-mud-b11jrchz-api.compute.c-5.eu-central-1.aws.neon.tech").replace(/\/+$/, "");
const ADMIN_USER = process.env.E2E_ADMIN_USERNAME;
const ADMIN_PASS = process.env.E2E_ADMIN_PASSWORD;
if (!ADMIN_USER || !ADMIN_PASS) throw new Error("E2E_ADMIN_USERNAME / E2E_ADMIN_PASSWORD requis");

const call = async (method, path, { body, token } = {}) => {
  const res = await fetch(BASE + path, {
    method,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null; try { json = await res.json(); } catch {}
  return { status: res.status, json };
};

const login = await call("POST", "/api/v1/auth/login", { body: { username: ADMIN_USER, password: ADMIN_PASS } });
const adminToken = login.json?.data?.token;
if (!adminToken) throw new Error("login admin a echoue: " + JSON.stringify(login.json));
console.log("login admin OK, role=" + login.json.data.role);

const gen = await call("POST", "/api/v1/admin/codes/generate", { token: adminToken, body: { count: 1 } });
const code = (gen.json?.data?.codes || [])[0];
console.log("code genere:", code);

const rnd = () => Math.floor(Math.random() * 1e10).toString().padStart(10, "0");
const bizId = "biz-e2e-" + rnd().slice(0, 8);
const phone = "+225" + rnd();
const reg = await call("POST", "/api/v1/register", {
  body: { activationCode: code, business: { id: bizId, name: "Alimentation Benie", ownerName: "Aya Benie", phone, sector: "alimentation" }, user: { fullName: "Aya Benie", phone } },
});
if (!reg.json?.data?.syncToken) throw new Error("register a echoue: " + JSON.stringify(reg.json));
console.log("boutique creee:", bizId);

// Smoke des nouvelles routes de lecture (attentes : 200 + status success/ok).
for (const p of ["/api/v1/admin/stats", "/api/v1/admin/subscriptions", "/api/v1/admin/field-activities", "/api/v1/admin/map-data", "/api/v1/admin/users", "/api/v1/admin/sync-logs", "/api/v1/admin/codes"]) {
  const r = await call("GET", p, { token: adminToken });
  console.log((r.status === 200 ? "OK  " : "ERR ") + p + " -> " + r.status + " " + JSON.stringify(r.json?.data ?? r.json?.message ?? "").slice(0, 90));
}

// Issue une licence pour que la licence active comptabilise.
await call("POST", "/api/v1/license/issue", { token: adminToken, body: { businessId: bizId, plan: "PRO", days: 30 } });
console.log("licence emise pour", bizId);

// Evenements d'analytique periode test (install 'e2e-%' -> purge) pour que
// l'onglet "Période test" du dashboard affiche des donnees reels.
const uid = () => crypto.randomUUID();
const snap = { salesCount: 12, soldFcfa: 36500, productsCount: 25, catalogActivatedCount: 6, customersCount: 4, expensesCount: 2, eventCount: 80, pendingCount: 0, openDays: 6, sector: "alimentation" };
const ing = await call("POST", "/api/v1/analytics/ingest", { body: {
  schema: "lynkstor.trial.v1", installId: "e2e-dash-" + rnd().slice(0, 6), sector: "alimentation",
  events: [
    { id: uid(), name: "app.opened", properties: {}, createdAt: new Date().toISOString() },
    { id: uid(), name: "sale.completed", properties: { amount: 2750 }, createdAt: new Date().toISOString() },
    { id: uid(), name: "snapshot.daily", properties: snap, createdAt: new Date().toISOString() },
  ],
} });
console.log("analytics ingestees:", JSON.stringify(ing.json?.data));
const summ = await call("GET", "/api/v1/admin/analytics/summary", { token: adminToken });
console.log("analytics/summary -> " + summ.status + " installs=" + summ.json?.data?.installs + " shops=" + (summ.json?.data?.shops || []).length);
console.log("\nNEXT: verifier dans le navigateur https://sweet-bush-a7e8.wosee-connect.workers.dev (login ephemere), puis tool/purge_neon_demo.sql. bizId=" + bizId);
