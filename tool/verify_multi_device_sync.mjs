// Vérification E2E "multi-postes" : deux appareils d'une MÊME boutique syncés
// via le gateway Neon. Le poste B rejoint la boutique du poste A par
// INVITATION CLOUD (invitations/create -> peek -> accept), SANS 2e code
// d'activation agent. On valide push A -> pull B, push B -> pull A
// (incrémental), l'ordre serveur global (server_seq), l'idempotence,
// l'isolation inter-commerces et les garde-fous d'invitation (code unique,
// used, inconnu, sans jeton).
//
// Prérequis : tool/seed_e2e_demo.ps1 exécuté avec E2E_ADMIN_USERNAME /
// E2E_ADMIN_PASSWORD (admin éphémère) et le code LYNK-E2E-AUTO disponible.
// Usage : node tool/verify_multi_device_sync.mjs
import crypto from "node:crypto";

const BASE = (process.env.NEON_API_BASE ||
  "https://br-curly-mud-b11jrchz-api.compute.c-5.eu-central-1.aws.neon.tech").replace(/\/+$/, "");
const ADMIN_USER = process.env.E2E_ADMIN_USERNAME;
const ADMIN_PASS = process.env.E2E_ADMIN_PASSWORD;
const CODE1 = "LYNK-E2E-AUTO";
if (!ADMIN_USER || !ADMIN_PASS) {
  console.error("E2E_ADMIN_USERNAME et E2E_ADMIN_PASSWORD requis (session shell de seed_e2e_demo.ps1).");
  process.exit(2);
}

let pass = 0, fail = 0;
const check = (name, cond, extra = "") => {
  if (cond) { pass++; console.log("PASS " + name + (extra ? " :: " + extra : "")); }
  else { fail++; console.log("FAIL " + name + (extra ? " :: " + extra : "")); }
};
async function call(method, path, { body, token, headers } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: "Bearer " + token } : {}),
      ...(headers || {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, json };
}
const rndPhone = () => "+225" + crypto.randomBytes(5).readUIntBE(0, 5).toString().padStart(10, "0").slice(0, 10);
const runId = crypto.randomBytes(3).toString("hex");
// biz-e2e-* -> nettoyé par tool/purge_neon_demo.sql
const bizA = "biz-e2e-md-" + runId;      // boutique partagée par les 2 postes
const bizOther = "biz-e2e-mdx-" + runId; // boutique voisine (isolation)
const deviceB = crypto.randomUUID();

// ——— 0. login admin (code d'activation pour la boutique voisine) ———
let r = await call("POST", "/api/v1/auth/login", { body: { username: ADMIN_USER, password: ADMIN_PASS } });
const adminToken = r.json?.data?.token;
check("admin login", r.status === 200 && !!adminToken);
if (!adminToken) { console.error("Impossible de continuer sans token admin."); process.exit(2); }

// ——— 1. poste A : enregistrement de la boutique (code semé) ———
const phoneA = rndPhone();
r = await call("POST", "/api/v1/register", {
  body: {
    activationCode: CODE1,
    business: { id: bizA, name: "Boutique Multi-Postes", ownerName: "Awa", phone: phoneA, sector: "general" },
    user: { fullName: "Awa (caissiere 1)", phone: phoneA },
  },
});
const tokenA = r.json?.data?.syncToken;
check("poste A enregistre (syncToken)", r.status === 200 && !!tokenA, "businessId=" + r.json?.data?.businessId);

// ——— 2. invitation cloud : le poste A génère un code pour le poste B ———
r = await call("POST", "/api/v1/invitations/create", { token: tokenA, body: { role: "seller" } });
const inviteCode = r.json?.data?.code;
check("invitation creee par le poste A (INV-XXXX-XXXX)",
  r.status === 200 && /^INV-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(inviteCode || ""), "code=" + inviteCode);

r = await call("POST", "/api/v1/invitations/create", { body: { role: "seller" } });
check("invitation sans jeton appareil refusee (401)", r.status === 401, "HTTP " + r.status);

// peek public : la poste B confirme avant de saisir son nom/PIN
r = await call("POST", "/api/v1/invitations/peek", { body: { code: inviteCode } });
check("peek public renvoie la boutique",
  r.status === 200 && r.json?.data?.businessId === bizA && r.json?.data?.businessName === "Boutique Multi-Postes",
  "role=" + r.json?.data?.role);
r = await call("POST", "/api/v1/invitations/peek", { body: { code: "INV-ZZZZ-ZZZZ" } });
check("peek code inconnu -> 404", r.status === 404, "HTTP " + r.status);

// ——— 3. poste B : accepte l'invitation -> 2e jeton appareil, 0 code agent ———
const phoneB = rndPhone();
r = await call("POST", "/api/v1/invitations/accept", {
  body: { code: inviteCode, deviceId: deviceB, fullName: "Kofi (caissier 2)", phone: phoneB },
});
const tokenB = r.json?.data?.syncToken;
check("poste B rejoint via invitation (2e syncToken)",
  r.status === 200 && !!tokenB && r.json?.data?.businessId === bizA && r.json?.data?.role === "seller",
  "userId=" + r.json?.data?.userId + " plan=" + r.json?.data?.planName);
check("jetons poste A et poste B distincts", !!tokenA && !!tokenB && tokenA !== tokenB);

r = await call("POST", "/api/v1/invitations/peek", { body: { code: inviteCode } });
check("peek apres usage -> 409 (code consomme)", r.status === 409, "HTTP " + r.status);
r = await call("POST", "/api/v1/invitations/accept", {
  body: { code: inviteCode, deviceId: crypto.randomUUID(), fullName: "Tentative reuse", phone: rndPhone() },
});
check("re-acceptation du meme code refusee (404/409)", r.status === 404 || r.status === 409, "HTTP " + r.status);

// ——— 4. poste A push (produit + vente), idempotent ———
const mk = (t, n, op = "upsert", v = 1) => ({
  id: bizA + ":" + t + ":" + n, businessId: bizA, entityType: t, entityId: t + "-" + n,
  operation: op, payload: { id: t + "-" + n, name: t + " " + n, version: v }, entityVersion: v,
});
r = await call("POST", "/api/v1/sync/push", { token: tokenA, body: { items: [mk("product", "A1"), mk("product", "A2")] }, headers: { "X-Idempotency-Key": "md-a-1" } });
check("push poste A accepte (2)", r.status === 200 && r.json?.data?.accepted === 2, JSON.stringify(r.json?.data));
r = await call("POST", "/api/v1/sync/push", { token: tokenA, body: { items: [mk("product", "A1"), mk("product", "A2")] }, headers: { "X-Idempotency-Key": "md-a-1" } });
check("replay meme idempotency-key -> deduped", r.status === 200 && r.json?.data?.deduped === true, JSON.stringify(r.json?.data));

// ——— 5. poste B PULL : doit voir les événements de A ———
r = await call("GET", "/api/v1/sync/pull?businessId=" + bizA + "&cursor=0", { token: tokenB });
const pulledByB = r.json?.data?.items || [];
const cursorB1 = Number(r.json?.data?.nextCursor || 0);
check("poste B recoit les events du poste A", r.status === 200 && pulledByB.some((e) => e.entityId === "product-A1") && pulledByB.some((e) => e.entityId === "product-A2"),
  "n=" + pulledByB.length + " cursor=" + cursorB1);

// ——— 6. poste A ancre son curseur AVANT le push de B, puis B push ———
r = await call("GET", "/api/v1/sync/pull?businessId=" + bizA + "&cursor=0", { token: tokenA });
const cursorA1 = Number(r.json?.data?.nextCursor || 0);
r = await call("POST", "/api/v1/sync/push", { token: tokenB, body: { items: [mk("product", "B1"), mk("sale", "B1")] }, headers: { "X-Idempotency-Key": "md-b-1" } });
check("push poste B accepte (2)", r.status === 200 && r.json?.data?.accepted === 2, JSON.stringify(r.json?.data));
r = await call("GET", "/api/v1/sync/pull?businessId=" + bizA + "&cursor=" + cursorA1, { token: tokenA });
const incA = r.json?.data?.items || [];
check("poste A recoit les events du poste B (incremental)", r.status === 200 && incA.some((e) => e.entityId === "product-B1") && incA.some((e) => e.entityId === "sale-B1"),
  "n=" + incA.length);
const drained = await call("GET", "/api/v1/sync/pull?businessId=" + bizA + "&cursor=" + Number(r.json?.data?.nextCursor), { token: tokenA });
check("pull incremental exclusif (plus rien apres)", drained.status === 200 && (drained.json?.data?.items || []).length === 0);

// ——— 7. server_seq : ordre global coherent entre postes ———
r = await call("GET", "/api/v1/sync/pull?businessId=" + bizA + "&cursor=0&limit=100", { token: tokenA });
const all = r.json?.data?.items || [];
const seqs = all.map((e) => e.serverSeq);
check("server_seq strictement croissant (tous postes confondus)", seqs.every((s, i) => i === 0 || s > seqs[i - 1]), "seq=" + seqs.join(","));
check("4 evenements au total pour la boutique", all.length === 4, "n=" + all.length);

// ——— 8. isolation : poste B ne peut PAS lire une autre boutique ———
const phoneC = rndPhone();
const g = await call("POST", "/api/v1/admin/codes/generate", { token: adminToken, body: { count: 1 } });
r = await call("POST", "/api/v1/register", {
  body: { activationCode: (g.json?.data?.codes || [])[0], business: { id: bizOther, name: "Boutique Voisine", ownerName: "Ibrahim", phone: phoneC, sector: "general" }, user: { fullName: "Ibrahim", phone: phoneC } },
});
const tokenC = r.json?.data?.syncToken;
const iso = await call("GET", "/api/v1/sync/pull?businessId=" + bizA + "&cursor=0", { token: tokenC });
check("poste d'une AUTRE boutique refuse (403)", iso.status === 403, "HTTP " + iso.status);

// ——— 9. jeton invalide refuse ———
const bad = await call("GET", "/api/v1/sync/pull?businessId=" + bizA + "&cursor=0", { token: "lynk_" + "0".repeat(64) });
check("jeton invalide refuse (401)", bad.status === 401, "HTTP " + bad.status);

console.log("\nRESULTAT : " + pass + " PASS / " + fail + " FAIL");
console.log("Nettoyage : tool/purge_neon_demo.sql (prefis biz-e2e-*)");
process.exit(fail ? 1 : 0);
