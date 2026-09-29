// End-to-end verification of the deployed Lynkstor Neon gateway.
// Usage: node tool/verify_neon_backend.mjs <BASE_URL>
const BASE = (process.argv[2] || "https://br-curly-mud-b11jrchz-api.compute.c-5.eu-central-1.aws.neon.tech").replace(/\/+$/, "");
import crypto from "node:crypto";

// Raw 32-byte Ed25519 public key (printed by gen_neon_secrets.mjs at creation).
const PUB_RAW_B64URL = process.env.LICENSE_PUBLIC_RAW_B64URL || "mCjVvBo2MH4jPxeWXcwHODoQyk2zT_4T1nesPV_otkM";
function spkiFromRaw(rawB64Url) {
  const raw = Buffer.from(rawB64Url, "base64url");
  const prefix = Buffer.from("302a300506032b6570032100", "hex");
  return crypto.createPublicKey({ key: Buffer.concat([prefix, raw]), format: "der", type: "spki" });
}

let pass = 0, fail = 0;
const check = (name, cond, extra = "") => {
  if (cond) { pass++; console.log("PASS " + name + (extra ? " :: " + extra : "")); }
  else { fail++; console.log("FAIL " + name + (extra ? " :: " + extra : "")); }
};
async function call(method, path, { body, token } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: "Bearer " + token } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch {}
  return { status: res.status, json };
}

const bizId = "biz-e2e-" + crypto.randomBytes(4).toString("hex");
const userId = "usr-e2e-" + crypto.randomBytes(4).toString("hex");
const runId = crypto.randomBytes(3).toString("hex"); // identifiants ephemeres (staff, code) auto-nettoyes
// Code d'activation utilisÃ© par ce run. Doit Ãªtre (re)semÃ© comme "available"
// juste avant le run (voir tool seed step), car /register le consomme.
const CODE = process.env.E2E_CODE || "LYNK-E2E-AUTO";
// Credentials admin utilises par /auth/login (etape 8) puis /license/issue.
// Ils sont EPHIMERES : tool/seed_e2e_demo.ps1 les (re)cree a partir de
// E2E_ADMIN_USERNAME/E2E_ADMIN_PASSWORD, et tool/purge_neon_demo.sql les
// supprime apres le run. Les defauts ci-dessous ne marchent plus en prod
// (le credential de demo y a ete purge) : c'est voulu.
const ADMIN_USER = process.env.E2E_ADMIN_USERNAME || "admin";
const ADMIN_PASS = process.env.E2E_ADMIN_PASSWORD || "admin123";
// users.phone has a UNIQUE index -> each fresh registration needs a unique phone.
const phone = "+225" + crypto.randomBytes(5).readUIntBE(0, 5).toString().padStart(10, "0").slice(0, 10);

// 1. health
let r = await call("GET", "/health");
check("health 200", r.status === 200 && r.json?.data?.service);

// 2. config
r = await call("GET", "/v1/config");
check("config shape", r.status === 200 && typeof r.json?.data?.minSupportedVersion === "string" && r.json?.data?.requireAgentActivationCode === true,
  JSON.stringify(r.json?.data));

// 3. register/validate (available code)
r = await call("POST", "/api/v1/register/validate", { body: { activationCode: CODE } });
check("validate code", r.status === 200 && r.json?.data?.planName === "STARTER", JSON.stringify(r.json?.data || r.json));

// 4. register
r = await call("POST", "/api/v1/register", {
  body: {
    activationCode: CODE,
    business: { id: bizId, name: "Boutique E2E", ownerName: "Koffi", phone, sector: "general" },
    user: { id: userId, fullName: "Koffi", phone },
  },
});
const syncToken = r.json?.data?.syncToken;
check("register returns syncToken", r.status === 200 && !!syncToken, "businessId=" + r.json?.data?.businessId);

// 4b. reuse same code must fail (idempotent/anti-replay)
const r2 = await call("POST", "/api/v1/register/validate", { body: { activationCode: CODE } });
check("code consumed (re-validate rejected)", r2.status >= 400, "HTTP " + r2.status);

// 5. sync push (batch)
const ev = (n) => ({
  id: bizId + ":product:" + n,
  businessId: bizId, entityType: "product", entityId: "prod-" + n,
  operation: "upsert", payload: { name: "Produit " + n, price: 100 * n },
  deviceId: "dev-e2e", entityVersion: 1,
});
r = await call("POST", "/api/v1/sync/push", {
  token: syncToken,
  body: { items: [ev(1), ev(2), ev(3)] },
});
// add idempotency header via manual fetch (call() doesn't set it): re-issue with header
{
  const res = await fetch(BASE + "/api/v1/sync/push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + syncToken, "X-Idempotency-Key": "batch-e2e-1" },
    body: JSON.stringify({ items: [ev(1), ev(2), ev(3)] }),
  });
  const j = await res.json().catch(() => null);
  check("sync push accepted", res.status === 200 && j?.data?.accepted >= 0, JSON.stringify(j?.data));
}

// 5b. idempotent replay with same key
{
  const res = await fetch(BASE + "/api/v1/sync/push", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + syncToken, "X-Idempotency-Key": "batch-e2e-1" },
    body: JSON.stringify({ items: [ev(1), ev(2), ev(3)] }),
  });
  const j = await res.json().catch(() => null);
  check("sync push idempotent replay", res.status === 200 && (j?.data?.deduped === true || j?.data?.accepted === 3), "HTTP " + res.status + " " + JSON.stringify(j));
}

// 6. sync pull
r = await call("GET", "/api/v1/sync/pull?businessId=" + bizId + "&cursor=0&limit=100", { token: syncToken });
const pulled = r.json?.data?.items || [];
check("sync pull returns events", r.status === 200 && Array.isArray(pulled) && pulled.length > 0, "n=" + pulled.length + " nextCursor=" + r.json?.data?.nextCursor);

// 6b. wrong business rejected
const badPull = await call("GET", "/api/v1/sync/pull?businessId=SOMEONE-ELSE&cursor=0", { token: syncToken });
check("pull cross-business rejected (S2)", badPull.status === 403, "HTTP " + badPull.status);

// 7. subscription status
r = await call("GET", "/api/v1/subscription/status", { token: syncToken });
check("subscription status", r.status === 200 && r.json?.data?.businessId === bizId && r.json?.data?.subscriptionStatus === "trial",
  JSON.stringify(r.json?.data));
check("no licenseToken before issue (trial)", r.json?.data?.licenseToken == null);

// 8. admin login
r = await call("POST", "/api/v1/auth/login", { body: { username: ADMIN_USER, password: ADMIN_PASS } });
const adminToken = r.json?.data?.token;
const adminStaffId = r.json?.data?.staffId;
check("admin login", r.status === 200 && !!adminToken, "role=" + r.json?.data?.role);

// 8b. bad password rejected
const badLogin = await call("POST", "/api/v1/auth/login", { body: { username: ADMIN_USER, password: ADMIN_PASS + "-invalide" } });
check("bad password rejected", badLogin.status === 401, "HTTP " + badLogin.status);

// 9. license issue (admin)
r = await call("POST", "/api/v1/license/issue", { token: adminToken, body: { businessId: bizId, plan: "PRO", days: 30 } });
const lic = r.json?.data?.token;
check("license issued", r.status === 200 && !!lic, "keyId=" + r.json?.data?.keyId);

// 9b. license without admin token rejected
const noAuth = await call("POST", "/api/v1/license/issue", { body: { businessId: bizId } });
check("license requires admin", noAuth.status === 401, "HTTP " + noAuth.status);

// 10. verify Ed25519 signature on the license with the public key
if (lic) {
  try {
    const [h, p, s] = lic.split(".");
    const signingInput = Buffer.from(h + "." + p, "utf8");
    const sig = Buffer.from(s, "base64url");
    const pub = spkiFromRaw(PUB_RAW_B64URL);
    const valid = crypto.verify(null, signingInput, pub, sig);
    const claims = JSON.parse(Buffer.from(p, "base64url").toString("utf8"));
    check("license Ed25519 signature valid", valid === true,
      "claims=" + JSON.stringify({ biz: claims.businessId, plan: claims.plan, key: claims.keyId }));
    check("license tamper rejected",
      crypto.verify(null, Buffer.from(h + "." + p + "x", "utf8"), pub, sig) === false);
  } catch (e) { check("license verify runnable", false, String(e)); }
}

// 11. subscription status now licenseActive (license unexpired) + returns raw signed token
r = await call("GET", "/api/v1/subscription/status", { token: syncToken });
check("licenseActive true after issue", r.json?.data?.licenseActive === true, JSON.stringify(r.json?.data));
const returnedToken = r.json?.data?.licenseToken;
check("status returns licenseToken after issue", typeof returnedToken === "string" && returnedToken.split(".").length === 3);
check("returned licenseToken equals the issued token", returnedToken === lic);
if (typeof returnedToken === "string" && returnedToken.split(".").length === 3) {
  try {
    const [rh, rp, rs] = returnedToken.split(".");
    const rvalid = crypto.verify(null, Buffer.from(rh + "." + rp, "utf8"), spkiFromRaw(PUB_RAW_B64URL), Buffer.from(rs, "base64url"));
    const rclaims = JSON.parse(Buffer.from(rp, "base64url").toString("utf8"));
    check("returned licenseToken Ed25519 signature valid", rvalid === true, "biz=" + rclaims.businessId + " plan=" + rclaims.plan);
    check("returned licenseToken bound to this business", rclaims.businessId === bizId);
  } catch (e) { check("returned licenseToken verify runnable", false, String(e)); }
}

// ——— 12. Routes dashboard admin ———
// Les donnees creees ici sont ephemeres et auto-nettoyees dans le run
// (code genere revoque, compte staff supprime). biz-e2e-% est purge par
// tool/purge_neon_demo.sql.

// 12a. KPIs
r = await call("GET", "/api/v1/admin/stats", { token: adminToken });
const st = r.json?.data || {};
check("admin/stats 200 + shape", r.status === 200 && typeof st.totalBusinesses === "number"
  && typeof st.activeLicenses === "number" && typeof st.availableCodes === "number", JSON.stringify(st));

// 12b. recherche entreprise (la boutique enregistree etait-elle presente ?)
r = await call("GET", "/api/v1/admin/businesses?q=" + bizId, { token: adminToken });
check("admin/businesses recherche par id", r.status === 200 && Array.isArray(r.json?.data)
  && r.json.data.some((b) => b.id === bizId), "n=" + (r.json?.data?.length ?? 0));

// 12c. generer un lot de codes (1) + preview + consommation reelle + revoke
r = await call("POST", "/api/v1/admin/codes/generate", { token: adminToken, body: { count: 1 } });
const gen = (r.json?.data?.codes || [])[0];
check("admin/codes/generate", r.status === 200 && typeof gen === "string" && /^LYNK-/.test(gen), "code=" + gen);

let pr = await call("POST", "/api/v1/admin/codes/preview", { token: adminToken, body: { code: gen } });
check("admin/codes/preview available", pr.status === 200 && pr.json?.data?.status === "available" && pr.json?.data?.plan_name === "STARTER",
  JSON.stringify(pr.json?.data || pr.json));

// consommation via le vrai tunnel mobile /register -> boucle de issuance fermee
const bizId2 = "biz-e2e-" + runId + "b";
const phone2 = "+225" + crypto.randomBytes(5).readUIntBE(0, 5).toString().padStart(10, "0").slice(0, 10);
pr = await call("POST", "/api/v1/register", {
  body: { activationCode: gen, business: { id: bizId2, name: "Boutique Code Genere", ownerName: "Aya", phone: phone2, sector: "general" }, user: { fullName: "Aya", phone: phone2 } },
});
const syncToken2 = pr.json?.data?.syncToken;
check("code genere consommable via /register", pr.status === 200 && !!syncToken2, pr.json?.message || ("HTTP " + pr.status));

pr = await call("POST", "/api/v1/admin/codes/preview", { token: adminToken, body: { code: gen } });
check("code passe a 'used' apres consommation", pr.status === 200 && pr.json?.data?.status === "used", "status=" + pr.json?.data?.status);

pr = await call("POST", "/api/v1/admin/codes/revoke", { token: adminToken, body: { code: gen } });
check("revoke d'un code 'used' refuse", pr.status >= 400, "HTTP " + pr.status);

// 12d. cycle revoke d'un code disponible (proprie -> laisse aucun residu)
r = await call("POST", "/api/v1/admin/codes/generate", { token: adminToken, body: { count: 1 } });
const gen2 = (r.json?.data?.codes || [])[0];
pr = await call("POST", "/api/v1/admin/codes/revoke", { token: adminToken, body: { code: gen2 } });
check("revoke d'un code 'available' reussit", pr.status === 200, JSON.stringify(pr.json));
pr = await call("POST", "/api/v1/admin/codes/preview", { token: adminToken, body: { code: gen2 } });
check("code désormais 'void' (revoque)", pr.status === 200 && pr.json?.data?.status === "void", "status=" + pr.json?.data?.status);

// 12e. staff : liste sans hash, creation pbkdf2, login, privilege, suppression
r = await call("GET", "/api/v1/admin/staff", { token: adminToken });
const staffList = r.json?.data || [];
check("admin/staff liste sans password_hash", r.status === 200 && Array.isArray(staffList)
  && staffList.every((s) => s.password_hash === undefined), "n=" + staffList.length);

const botUser = "e2e-bot-" + runId;
const botPass = "E2eBot-" + runId + "-Sup3rLongPass";
r = await call("POST", "/api/v1/admin/staff", { token: adminToken, body: { full_name: "Bot E2E", username: botUser, password: botPass, role: "commercial" } });
const newStaffId = r.json?.data?.id;
check("admin/staff create (pbkdf2)", r.status === 200 && !!newStaffId && r.json?.data?.role === "commercial", "id=" + newStaffId);

pr = await call("POST", "/api/v1/admin/staff", { token: adminToken, body: { full_name: "Trop Court", username: "e2e-short-" + runId, password: "courts", role: "commercial" } });
check("admin/staff mot de passe court refuse", pr.status >= 400, "HTTP " + pr.status);

pr = await call("POST", "/api/v1/auth/login", { body: { username: botUser, password: botPass } });
const botToken = pr.json?.data?.token;
check("staff pbkdf2 cree peut se logger", pr.status === 200 && !!botToken, "role=" + pr.json?.data?.role);

pr = await call("GET", "/api/v1/admin/stats", { token: botToken });
check("commercial refuse sur route admin (403)", pr.status === 403, "HTTP " + pr.status);

pr = await call("POST", "/api/v1/license/issue", { token: botToken, body: { businessId: bizId, plan: "PRO", days: 30 } });
check("commercial refuse sur /license/issue (403)", pr.status === 403, "HTTP " + pr.status);

pr = await call("DELETE", "/api/v1/admin/staff", { token: adminToken, body: { id: newStaffId } });
check("admin/staff delete (super_admin)", pr.status === 200, JSON.stringify(pr.json?.data || pr.json));

// 12f. cycle complet licence : issue -> active -> revoke -> inactive (bizId2, dont on tient le syncToken)
r = await call("POST", "/api/v1/license/issue", { token: adminToken, body: { businessId: bizId2, plan: "PRO", days: 30 } });
check("license issue pour bizId2 (avant revoke)", r.status === 200 && !!r.json?.data?.token, "keyId=" + r.json?.data?.keyId);
r = await call("POST", "/api/v1/admin/license/revoke", { token: adminToken, body: { businessId: bizId2 } });
check("admin/license/revoke (super_admin)", r.status === 200 && r.json?.data?.revoked >= 1, JSON.stringify(r.json?.data || r.json));
pr = await call("GET", "/api/v1/subscription/status", { token: syncToken2 });
check("licenseActive false apres revoke (bizId2)", pr.status === 200 && pr.json?.data?.licenseActive === false,
  "licenseActive=" + pr.json?.data?.licenseActive);

// ——— 13. Analytique periode test + activation express + edition abonnement ———
// Les evenements analytics portent install_id 'e2e-<runId>' -> purges par
// tool/purge_neon_demo.sql (install_id LIKE 'e2e-%').

// 13a. ingest : 3 evenements valides + 1 nom inconnu (ignore) + replay idempotent
const installId = "e2e-" + runId;
const uuid = () => crypto.randomUUID();
const evIds = [uuid(), uuid(), uuid()];
const ingestBody = {
  schema: "lynkstor.trial.v1",
  installId,
  sector: "alimentation",
  events: [
    { id: evIds[0], name: "app.opened", properties: {}, createdAt: new Date().toISOString() },
    { id: evIds[1], name: "sale.completed", properties: { amount: 2500 }, createdAt: new Date().toISOString() },
    { id: evIds[2], name: "snapshot.daily", properties: {
      salesCount: 7, soldFcfa: 12500, productsCount: 3, catalogActivatedCount: 1,
      customersCount: 2, expensesCount: 0, eventCount: 42, pendingCount: 0, openDays: 5,
      sector: "alimentation",
    }, createdAt: new Date().toISOString() },
    { id: uuid(), name: "pii.attempt", properties: {}, createdAt: new Date().toISOString() },
  ],
};
r = await call("POST", "/api/v1/analytics/ingest", { body: ingestBody });
check("analytics/ingest accepte 3 (nom inconnu jete)", r.status === 200 && r.json?.data?.accepted === 3, JSON.stringify(r.json?.data || r.json));

r = await call("POST", "/api/v1/analytics/ingest", { body: ingestBody });
check("analytics/ingest idempotent (replay = 0)", r.status === 200 && r.json?.data?.accepted === 0, JSON.stringify(r.json?.data));

r = await call("POST", "/api/v1/analytics/ingest", { body: { installId: "", events: [] } });
check("analytics/ingest sans installId refuse", r.status === 400, "HTTP " + r.status);

// 13b. summary (enveloppe 'success' du dashboard)
r = await call("GET", "/api/v1/admin/analytics/summary", { token: adminToken });
const sum = r.json?.data || {};
const ourShop = (sum.shops || []).find((s) => s.install_id === installId);
check("analytics/summary success + notre install", r.status === 200 && r.json?.status === "success"
  && sum.installs >= 1 && !!ourShop, "installs=" + sum.installs + " events=" + sum.events);
check("analytics/summary compteurs du snapshot", ourShop && ourShop.sales_count === 7 && Number(ourShop.sold_fcfa) === 12500
  && ourShop.open_days === 5 && ourShop.sector === "alimentation", JSON.stringify(ourShop));
check("analytics/summary par nom d'evenement", (sum.byEvent || {})["app.opened"] >= 1, JSON.stringify(sum.byEvent || {}));

// 13c. export brut
r = await call("GET", "/api/v1/admin/analytics/export", { token: adminToken });
const exportedRows = r.json?.data || [];
check("analytics/export contient nos evenements", r.status === 200 && Array.isArray(exportedRows)
  && exportedRows.some((e) => e.install_id === installId && e.event_name === "sale.completed"), "n=" + exportedRows.length);
pr = await call("GET", "/api/v1/admin/analytics/export", { token: botToken });
check("token du staff SUPPRIME revoque (401, plus 403)", pr.status === 401, "HTTP " + pr.status);

// 13d. activation express : staff commercial dedie + abonnement bizId active
const actStaff = "e2e-act-" + runId;
r = await call("POST", "/api/v1/admin/staff", { token: adminToken, body: { full_name: "Agent Terrain", username: actStaff, password: "E2eAct-" + runId + "-LongPass1", role: "commercial" } });
const actStaffId = r.json?.data?.id;
check("staff commercial pour activation cree", r.status === 200 && !!actStaffId, "id=" + actStaffId);

r = await call("POST", "/api/v1/admin/commercial/activate", { token: adminToken, body: {
  business_id: bizId, staff_id: actStaffId, plan_name: "PRO (Mensuel)", price_fcfa: 15000, duration_months: 1, notes: "E2E activation express",
} });
check("commercial/activate (200 + date d'expiration)", r.status === 200 && /^\d{4}-\d{2}-\d{2}$/.test(String(r.json?.data?.expiresAt || "")), JSON.stringify(r.json?.data || r.json));

pr = await call("GET", "/api/v1/admin/subscriptions", { token: adminToken });
const bizSub = (pr.json?.data || []).find((s) => s.business_id === bizId);
check("abonnement bizId passe a active", pr.status === 200 && bizSub?.status === "active" && bizSub?.plan_name === "PRO (Mensuel)",
  JSON.stringify(bizSub && { s: bizSub.status, p: bizSub.plan_name }));

pr = await call("GET", "/api/v1/admin/field-activities", { token: adminToken });
check("field_activities journalise l'activation", pr.status === 200 && (pr.json?.data || []).some((a) =>
  a.business_id === bizId && a.staff_id === actStaffId && a.activity_type === "activation" && Number(a.amount_collected_fcfa) === 15000));

pr = await call("POST", "/api/v1/admin/commercial/activate", { token: adminToken, body: { business_id: "inconnu-xx", staff_id: actStaffId } });
check("activation sur commerce inconnu refusee", pr.status === 404, "HTTP " + pr.status);

// 13e. edition d'abonnement (PUT /admin/subscriptions/:id)
const subId = bizSub?.id;
check("subscription id disponible pour PUT", !!subId, "id=" + subId);
r = await call("PUT", "/api/v1/admin/subscriptions/" + subId, { token: adminToken, body: {
  plan_name: "PRO (Mensuel)", price_fcfa: 15000, status: "suspended", expires_at: "2026-12-31",
} });
check("PUT subscription -> suspended", r.status === 200 && r.json?.status === "ok", JSON.stringify(r.json?.data || r.json));
pr = await call("PUT", "/api/v1/admin/subscriptions/" + subId, { token: adminToken, body: {
  plan_name: "PRO (Mensuel)", price_fcfa: 15000, status: "bogus", expires_at: "2026-12-31",
} });
check("PUT subscription status invalide refuse", pr.status === 400, "HTTP " + pr.status);
pr = await call("PUT", "/api/v1/admin/subscriptions/00000000-0000-0000-0000-000000000000", { token: adminToken, body: {
  plan_name: "X", price_fcfa: 1, status: "active", expires_at: "",
} });
check("PUT subscription id inconnu -> 404", pr.status === 404, "HTTP " + pr.status);

// menage : le staff d'activation n'est plus necessaire (bizId + events = purge)
pr = await call("DELETE", "/api/v1/admin/staff", { token: adminToken, body: { id: actStaffId } });
check("staff d'activation supprime (menage)", pr.status === 200, "HTTP " + pr.status);

// ——— 14. Revocation de sessions admin (token_version) ———
// Cycle : login -> session valide -> reset mdp = anciennes sessions 401 ->
// desactivation = login bloque -> reactivation + changement role effectif.
const revUser = "e2e-rev-" + runId;
const revPass1 = "E2eRev1-" + runId + "-LongPassA";
const revPass2 = "E2eRev2-" + runId + "-LongPassB";
r = await call("POST", "/api/v1/admin/staff", { token: adminToken, body: { full_name: "Bot Revocation", username: revUser, password: revPass1, role: "supervisor" } });
const revId = r.json?.data?.id;
check("staff supervisor cree (revocation)", r.status === 200 && !!revId, "id=" + revId);

pr = await call("POST", "/api/v1/auth/login", { body: { username: revUser, password: revPass1 } });
const revToken1 = pr.json?.data?.token;
check("login revocation P1", pr.status === 200 && !!revToken1, "role=" + pr.json?.data?.role);

pr = await call("GET", "/api/v1/admin/stats", { token: revToken1 });
check("supervisor lit admin/stats (200)", pr.status === 200, "HTTP " + pr.status);

// 14b. validations d'entree
pr = await call("POST", "/api/v1/admin/staff/update", { token: adminToken, body: { id: revId } });
check("update sans champ modifiable refuse", pr.status >= 400, "HTTP " + pr.status);
pr = await call("POST", "/api/v1/admin/staff/update", { token: adminToken, body: { id: revId, status: "bogus" } });
check("update status invalide refuse", pr.status >= 400, "HTTP " + pr.status);
pr = await call("POST", "/api/v1/admin/staff/update", { token: adminToken, body: { id: "inconnu-xx", status: "disabled" } });
check("update id inconnu -> 404", pr.status === 404, "HTTP " + pr.status);
pr = await call("POST", "/api/v1/admin/staff/update", { token: adminToken, body: { id: adminStaffId, status: "disabled" } });
check("auto-desactivation de son propre compte refusee", pr.status >= 400, "HTTP " + pr.status);

// 14c. reset mot de passe -> token emise avant = 401, P1 refuse, P2 accepte
r = await call("POST", "/api/v1/admin/staff/update", { token: adminToken, body: { id: revId, password: revPass2 } });
check("update password (tv bump)", r.status === 200 && Number(r.json?.data?.tokenVersion) >= 2, JSON.stringify(r.json?.data || r.json));
pr = await call("GET", "/api/v1/admin/stats", { token: revToken1 });
check("session emise AVANT reset mdp revoquee (401)", pr.status === 401, "HTTP " + pr.status);
pr = await call("POST", "/api/v1/auth/login", { body: { username: revUser, password: revPass1 } });
check("ancien mot de passe refuse", pr.status === 401, "HTTP " + pr.status);
pr = await call("POST", "/api/v1/auth/login", { body: { username: revUser, password: revPass2 } });
const revToken2 = pr.json?.data?.token;
check("nouveau mot de passe accepted (relogin)", pr.status === 200 && !!revToken2);

// 14d. desactivation -> session vivante meure + login bloque, puis reactivation
r = await call("POST", "/api/v1/admin/staff/update", { token: adminToken, body: { id: revId, status: "disabled" } });
check("update status disabled", r.status === 200 && r.json?.data?.status === "disabled", JSON.stringify(r.json?.data));
pr = await call("GET", "/api/v1/admin/stats", { token: revToken2 });
check("session vivante revoquee par desactivation (401)", pr.status === 401, "HTTP " + pr.status);
pr = await call("POST", "/api/v1/auth/login", { body: { username: revUser, password: revPass2 } });
check("login sur compte desactive refuse", pr.status === 401, "HTTP " + pr.status);
pr = await call("POST", "/api/v1/admin/staff/update", { token: adminToken, body: { id: revId, status: "active", role: "commercial" } });
check("reactivation + role commercial", pr.status === 200 && pr.json?.data?.status === "active" && pr.json?.data?.role === "commercial", JSON.stringify(pr.json?.data));
pr = await call("POST", "/api/v1/auth/login", { body: { username: revUser, password: revPass2 } });
const revToken3 = pr.json?.data?.token;
check("relogin role commercial", pr.status === 200 && pr.json?.data?.role === "commercial");
pr = await call("GET", "/api/v1/admin/stats", { token: revToken3 });
check("commercial de nouveau 403 (matrice intacte)", pr.status === 403, "HTTP " + pr.status);

// 14e. le token admin n'a JAMAIS ete affecte par les bumps d'autres comptes
pr = await call("POST", "/api/v1/admin/staff/update", { token: adminToken, body: { id: revId, status: "disabled" } });
check("adminToken toujours valide apres 3 bumps (200)", pr.status === 200, "HTTP " + pr.status);

// menage
pr = await call("DELETE", "/api/v1/admin/staff", { token: adminToken, body: { id: revId } });
check("staff de revocation supprime (menage)", pr.status === 200, "HTTP " + pr.status);

console.log("\n==== SUMMARY: " + pass + " passed, " + fail + " failed ====");
process.exit(fail ? 1 : 0);
