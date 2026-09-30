/**
 * Lynkstor Neon Function — API gateway (backend complet, offline-first).
 *
 * Portable depuis la Edge Function Deno Supabase : runtime Node 24, handler
 * web-standard `fetch`, Postgres du schéma `lynkstor` via pool `pg`
 * (`DATABASE_URL` injecté automatiquement par Neon).
 *
 * Routes (contrat exact du client Flutter) :
 *   GET  /                         health (public)
 *   GET  /health                   health (public)
 *   GET  /v1/config                runtime config force-update / kill-switch (public)
 *   POST /api/v1/register/validate pré-vérif code agent (apikey)
 *   POST /api/v1/register          inscription business + jeton appareil (apikey)
 *   GET  /api/v1/subscription/status  statut abonnement (Bearer jeton appareil)
 *   POST /api/v1/invitations/create   code d'invitation multi-postes (Bearer jeton appareil)
 *   POST /api/v1/invitations/peek     prévisualisation publique d'un code
 *   POST /api/v1/invitations/accept   rejoindre une boutique -> 2e jeton appareil
 *   POST /api/v1/sync/push         batch idempotent (Bearer jeton appareil)
 *   GET  /api/v1/sync/pull         delta events > cursor (Bearer jeton appareil)
 *   POST /api/v1/auth/login        session admin dashboard (HMAC)
 *   POST /api/v1/license/issue     licence signée Ed25519 (session admin)
 *   POST /api/v1/webhooks/payment  webhook agrégateur (signature HMAC)
 *   POST /api/v1/payments/initiate          dépôt PawaPay (Bearer jeton appareil)
 *   GET  /api/v1/payments/{intentId}        statut + réconciliation PawaPay
 *   POST /api/v1/payments/pawapay/webhook   callback PawaPay (ré-interrogé, jamais cru)
 */
import { Pool } from "pg";
import { attachDatabasePool } from "@neon/functions";
import crypto from "node:crypto";

// ————————————————————————————————————————————————————————————— Env & DB ———
const env = (k: string, d = ""): string => process.env[k] ?? d;

const CORS_ALLOWED_ORIGIN = env("CORS_ALLOWED_ORIGIN", "*");
const ADMIN_SESSION_SECRET = env("ADMIN_SESSION_SECRET");
const PAYMENT_WEBHOOK_SECRET = env("PAYMENT_WEBHOOK_SECRET");
const LICENSE_KEY_ID = env("LICENSE_KEY_ID", "default");
const LICENSE_PRIVATE_KEY_B64 = env("LICENSE_PRIVATE_KEY_B64");

// ————————————————————————————————————————————————————————— PawaPay (Mobile Money) ———
const PAWAPAY_API_TOKEN = env("PAWAPAY_API_TOKEN");
const PAWAPAY_API_BASE = env("PAWAPAY_API_BASE", "https://api.pawapay.io").replace(/\/+$/, "");
const PAWAPAY_COUNTRY = env("PAWAPAY_COUNTRY", "CM");
const PAWAPAY_CURRENCY = env("PAWAPAY_CURRENCY", "XAF");
const PAWAPAY_DIAL_CODE = env("PAWAPAY_DIAL_CODE", "237");
const PAWAPAY_DEPOSIT_MIN = parseInt(env("PAWAPAY_DEPOSIT_MIN", "50"), 10);
// Canaux exposés dans l'app → codes correspondants PawaPay (surchargeable par env).
const PAWAPAY_CORRESPONDENTS: Record<string, string> = {
  orange_money: env("PAWAPAY_CORR_ORANGE", "ORANGE_MONEY_CMR"),
  mtn_momo: env("PAWAPAY_CORR_MTN", "MTN_MOMO_CMR"),
};
const MONTHS_BY_BILLING_PERIOD: Record<string, number> = { monthly: 1, quarterly: 3, annual: 12 };

// Pool créé une seule fois au niveau module (réutilisé entre requêtes).
// Le pooler Neon (mode transaction) refuse le paramètre de démarrage
// `options` (search_path) : on utilise donc la connexion DIRECTE non poolée,
// qui l'accepte et applique search_path = lynkstor à toutes les tables.
const pool = new Pool({
  connectionString: process.env.DATABASE_URL_UNPOOLED || process.env.DATABASE_URL,
  max: 5,
  options: "-c search_path=lynkstor,public",
});
// eslint-disable-next-line @typescript-eslint/no-explicit-any
attachDatabasePool(pool as any);

let _licenseKey: crypto.KeyObject | null = null;
function licensePrivateKey(): crypto.KeyObject | null {
  if (_licenseKey) return _licenseKey;
  if (!LICENSE_PRIVATE_KEY_B64) return null;
  try {
    const pem = Buffer.from(LICENSE_PRIVATE_KEY_B64, "base64").toString("utf8");
    _licenseKey = crypto.createPrivateKey(pem);
    return _licenseKey;
  } catch {
    return null;
  }
}

// ————————————————————————————————————————————————————————————— Crypto utils ———
function b64url(input: Buffer | string): string {
  const buf = typeof input === "string" ? Buffer.from(input, "utf8") : input;
  return buf.toString("base64url");
}
function fromB64url(s: string): Buffer {
  return Buffer.from(s, "base64url");
}
function sha256hex(s: string): string {
  return crypto.createHash("sha256").update(s, "utf8").digest("hex");
}
function hmacHex(secret: string, data: string): string {
  return crypto.createHmac("sha256", secret).update(data, "utf8").digest("hex");
}
function safeEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a || "", "utf8");
  const bb = Buffer.from(b || "", "utf8");
  if (ba.length !== bb.length) return false;
  return crypto.timingSafeEqual(ba, bb);
}
function newSyncToken(): string {
  return "lynk_" + crypto.randomBytes(33).toString("base64url");
}
function newActivationCode(): string {
  // Format lisible type agent : LYNK-XXXX-XXXX (A-Z0-9, sans vowels ambigus).
  const alpha = "BCDFGHJKLMNPQRSTVWXYZ23456789";
  const pick = (n: number) =>
    Array.from(crypto.randomBytes(n)).map((b) => alpha[b % alpha.length]).join("");
  return `LYNK-${pick(4)}-${pick(4)}`;
}

// Mot de passe stocké au format : pbkdf2-sha256$<iter>$<saltHex>$<hashHex>
function verifyPassword(password: string, stored: string | null): boolean {
  if (!password || !stored) return false;
  const parts = stored.split("$");
  if (parts.length !== 4 || parts[0] !== "pbkdf2-sha256") return false; // S7
  const iter = parseInt(parts[1], 10);
  const salt = Buffer.from(parts[2], "hex");
  const want = Buffer.from(parts[3], "hex");
  if (!iter || !salt.length || !want.length) return false;
  const got = crypto.pbkdf2Sync(password, salt, iter, want.length, "sha256");
  return got.length === want.length && crypto.timingSafeEqual(got, want);
}
export function hashPassword(password: string, iter = 210000): string {
  const salt = crypto.randomBytes(16);
  const hash = crypto.pbkdf2Sync(password, salt, iter, 32, "sha256");
  return `pbkdf2-sha256$${iter}$${salt.toString("hex")}$${hash.toString("hex")}`;
}

// ————————————————————————————————————————————————————————————— Session admin ———
interface AdminSession {
  sub: string;
  role: string;
  exp: number;
  tv: number; // token_version au moment du login ; revalidé en base à chaque requête admin
}
function createAdminSessionToken(sub: string, role: string, tv = 1, ttlSec = 43200): string {
  const payload: AdminSession = { sub, role, tv, exp: Math.floor(Date.now() / 1000) + ttlSec };
  const body = b64url(JSON.stringify(payload));
  const sig = hmacHex(ADMIN_SESSION_SECRET, body);
  return `${body}.${sig}`;
}
function getAdminSession(req: Request): AdminSession | null {
  const h = req.headers.get("authorization") || "";
  const token = h.toLowerCase().startsWith("bearer ") ? h.slice(7).trim() : "";
  if (!token || !ADMIN_SESSION_SECRET) return null;
  const dot = token.indexOf(".");
  if (dot <= 0) return null;
  const body = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  if (!safeEqual(sig, hmacHex(ADMIN_SESSION_SECRET, body))) return null;
  try {
    const s = JSON.parse(fromB64url(body).toString("utf8")) as AdminSession;
    if (!s.sub || !s.exp || s.exp < Math.floor(Date.now() / 1000)) return null;
    return { ...s, tv: Number(s.tv ?? 0) };
  } catch {
    return null;
  }
}

// Revalidation en base d'une session HMAC : compte toujours présent, actif, et
// token_version inchangé (sinon = révoqué). Le rôle est RELU en base : une
// promotion/rétrogradation est effective immédiatement, pas à la reconnexion.
async function liveAdminSession(req: Request): Promise<AdminSession | Response> {
  const session = getAdminSession(req);
  if (!session) return err(req, "Session admin requise.", 401);
  const { rows } = await pool.query(
    `SELECT role, status, token_version FROM staff_accounts WHERE id = $1`,
    [session.sub],
  );
  if (!rows.length || rows[0].status !== "active" || Number(rows[0].token_version) !== session.tv)
    return err(req, "Session révoquée : reconnectez-vous.", 401);
  return { ...session, role: rows[0].role ?? session.role };
}

// Garde des routes admin : renvoie la session, ou une Response 401/403.
// Le rôle `commercial` n'accède à aucune route /api/v1/admin/* (il n'a qu'un
// accès applicatif via l'app mobile). super_admin = tous droits, supervisor =
// lecture + génération/révocation de codes + staff.
async function requireAdmin(req: Request, write = false): Promise<AdminSession | Response> {
  const session = await liveAdminSession(req);
  if (session instanceof Response) return session;
  if (session.role === "commercial") return err(req, "Rôle insuffisant.", 403);
  if (write && !["super_admin", "supervisor"].includes(session.role))
    return err(req, "Rôle insuffisant.", 403);
  return session;
}
function isAdminResponse(v: unknown): v is Response {
  return v instanceof Response;
}

// ————————————————————————————————————————————————————————————— Device token ———
interface DeviceAuth {
  businessId: string;
  deviceId: string;
}
async function authDevice(req: Request): Promise<DeviceAuth | null> {
  const h = req.headers.get("authorization") || "";
  const token = h.toLowerCase().startsWith("bearer ") ? h.slice(7).trim() : "";
  if (!token) return null;
  const hash = sha256hex(token);
  const { rows } = await pool.query(
    `SELECT business_id, device_id FROM device_sync_tokens
       WHERE token_hash = $1 AND revoked_at IS NULL`,
    [hash],
  );
  if (!rows.length) return null;
  pool.query(`UPDATE device_sync_tokens SET last_used_at = now() WHERE token_hash = $1`, [hash]).catch(() => {});
  return { businessId: rows[0].business_id, deviceId: rows[0].device_id ?? "" };
}

// ————————————————————————————————————————————————————————————— Licence Ed25519 ———
interface LicenseClaims {
  businessId: string;
  plan: string;
  issuedAt: number;
  expiresAt: number;
  nonce: string;
  keyId: string;
  graceDays: number;
}
function signLicense(claims: LicenseClaims): string | null {
  const key = licensePrivateKey();
  if (!key) return null;
  const header = { alg: "Ed25519", typ: "JWT", kid: claims.keyId };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const sig = crypto.sign(null, Buffer.from(signingInput, "utf8"), key);
  return `${signingInput}.${b64url(sig)}`;
}

// ————————————————————————————————————————————————————————————— HTTP helpers ———
function cors(req: Request): Record<string, string> {
  const origin = req.headers.get("origin");
  const allow = CORS_ALLOWED_ORIGIN === "*"
    ? "*"
    : (origin && CORS_ALLOWED_ORIGIN.split(",").map((s) => s.trim()).includes(origin) ? origin : "");
  const headers: Record<string, string> = {
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,apikey,X-Idempotency-Key,X-Webhook-Signature,X-Signature",
    "Access-Control-Max-Age": "86400",
  };
  if (allow) {
    headers["Access-Control-Allow-Origin"] = allow;
    if (allow !== "*") headers["Vary"] = "Origin";
  }
  return headers;
}
function json(req: Request, data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...cors(req) },
  });
}
const ok = (req: Request, data: unknown, message?: string) =>
  json(req, { status: "ok", data, ...(message ? { message } : {}) });
const err = (req: Request, message: string, status = 400) =>
  json(req, { status: "error", message }, status);

async function readJson(req: Request): Promise<Record<string, any>> {
  try {
    return (await req.json()) as Record<string, any>;
  } catch {
    return {};
  }
}

// ————————————————————————————————————————————————————————————— Handlers ———
async function handleConfig(req: Request): Promise<Response> {
  const data: Record<string, unknown> = {
    minSupportedVersion: env("MIN_SUPPORTED_VERSION", "1.0.0"),
    latestVersion: env("LATEST_VERSION", "1.2.0"),
    maintenance: env("MAINTENANCE", "false") === "true",
    killModules: env("KILL_MODULES", "").split(",").map((s) => s.trim()).filter(Boolean),
    maxOfflineDays: parseInt(env("MAX_OFFLINE_DAYS", "30"), 10),
    requireAgentActivationCode: env("REQUIRE_AGENT_ACTIVATION_CODE", "true") === "true",
    serverTime: new Date().toISOString(),
  };
  // La base (app_config) a préséance sur les defaults d'env quand présente.
  try {
    const { rows } = await pool.query(
      `SELECT key, value FROM app_config WHERE key IN ('version_policy','feature_flags')`,
    );
    for (const r of rows) {
      const v = typeof r.value === "string" ? JSON.parse(r.value) : r.value || {};
      if (r.key === "version_policy") {
        if (v.minSupportedVersion) data.minSupportedVersion = v.minSupportedVersion;
        if (v.latestVersion) data.latestVersion = v.latestVersion;
        if (typeof v.maintenance === "boolean") data.maintenance = v.maintenance;
        if (v.maxOfflineDays != null) data.maxOfflineDays = v.maxOfflineDays;
      } else if (r.key === "feature_flags") {
        if (Array.isArray(v.killModules)) data.killModules = v.killModules;
        if (typeof v.requireAgentActivationCode === "boolean")
          data.requireAgentActivationCode = v.requireAgentActivationCode;
      }
    }
  } catch { /* env fallback suffit */ }
  return ok(req, data);
}

async function handleRegisterValidate(req: Request): Promise<Response> {
  const body = await readJson(req);
  const code = String(body.activationCode || "").trim().toUpperCase();
  if (!code) return err(req, "Code d'activation manquant.");
  const { rows } = await pool.query(
    `SELECT rc.code, rc.status, p.name AS plan_name, p.price_fcfa
       FROM registration_codes rc
       LEFT JOIN plans p ON p.id = rc.plan_id
      WHERE rc.code = $1`,
    [code],
  );
  if (!rows.length) return err(req, "Code inconnu ou expiré.", 404);
  if (rows[0].status !== "available") return err(req, "Ce code a déjà été utilisé.", 409);
  return ok(req, { planName: rows[0].plan_name || env("TRIAL_PLAN_NAME", "STARTER"), expiresAt: null });
}

async function handleRegister(req: Request): Promise<Response> {
  const body = await readJson(req);
  const code = String(body.activationCode || "").trim().toUpperCase();
  const biz = body.business || {};
  const usr = body.user || {};
  const businessId = String(biz.id || "").trim();
  const userId = String(usr.id || "").trim() || crypto.randomUUID();
  const name = String(biz.name || "").trim();
  const ownerName = String(biz.ownerName || usr.fullName || "").trim();
  const phone = String(biz.phone || usr.phone || "").trim();
  const sector = String(biz.sector || "general").trim();
  if (!businessId || !name) return err(req, "Paramètres d'entreprise manquants.");
  if (!code) return err(req, "Code d'activation requis.");

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    // Verrouille & consomme le code de façon atomique (idempotent).
    const codes = await client.query(
      `SELECT id, status, plan_id, assigned_staff FROM registration_codes
         WHERE code = $1 FOR UPDATE`,
      [code],
    );
    if (!codes.rows.length) {
      await client.query("ROLLBACK");
      return err(req, "Code inconnu.", 404);
    }
    if (codes.rows[0].status !== "available") {
      await client.query("ROLLBACK");
      return err(req, "Ce code a déjà été utilisé.", 409);
    }
    const planId = codes.rows[0].plan_id;

    // Entreprise (idempotent sur id).
    await client.query(
      `INSERT INTO businesses (id, name, sector, phone, owner_name, status)
       VALUES ($1,$2,$3,$4,$5,'active')
       ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, updated_at=now()`,
      [businessId, name, sector, phone, ownerName],
    );
    await client.query(
      `INSERT INTO users (id, business_id, full_name, phone, role, status)
       VALUES ($1,$2,$3,$4,'owner','active')
       ON CONFLICT (id) DO NOTHING`,
      [userId, businessId, ownerName, phone],
    );

    // Plan + abonnement trial.
    let planName = env("TRIAL_PLAN_NAME", "STARTER");
    let price = parseFloat(env("TRIAL_PRICE_FCFA", "15000"));
    if (planId) {
      const pr = await client.query(`SELECT name, price_fcfa FROM plans WHERE id=$1`, [planId]);
      if (pr.rows.length) {
        planName = pr.rows[0].name || planName;
        price = parseFloat(pr.rows[0].price_fcfa) || price;
      }
    }
    const trialDays = parseInt(env("TRIAL_DAYS", "14"), 10);
    const subId = crypto.randomUUID();
    await client.query(
      `INSERT INTO subscriptions (id, business_id, plan_id, plan_name, status, price_fcfa, started_at, expires_at)
       VALUES ($1,$2,$3,$4,'trial',$5, now(), now() + make_interval(days => $6::int))
       ON CONFLICT (id) DO NOTHING`,
      [subId, businessId, planId, planName, price, trialDays],
    );
    await client.query(
      `UPDATE registration_codes SET status='used', used_by_business=$2, used_at=now() WHERE code=$1`,
      [code, businessId],
    );

    // Jeton appareil.
    const token = newSyncToken();
    const deviceId = String(usr.deviceId || crypto.randomUUID());
    await client.query(
      `INSERT INTO device_sync_tokens (id, business_id, device_id, token_hash)
       VALUES ($1,$2,$3,$4)`,
      [crypto.randomUUID(), businessId, deviceId, sha256hex(token)],
    );

    await client.query("COMMIT");
    return ok(req, {
      businessId,
      userId,
      syncToken: token,
      syncEndpoint: new URL(req.url).origin + "/api/v1/sync/push",
      planName: planName || "STARTER",
      expiresAt: null,
    });
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("register error", e);
    return err(req, "Échec de l'inscription.", 500);
  } finally {
    client.release();
  }
}
async function handleSubscriptionStatus(req: Request): Promise<Response> {
  const dev = await authDevice(req);
  if (!dev) return err(req, "Non autorisé.", 401);
  // Filet de sécurité offline-first : si une intention de paiement est encore en
  // attente (app fermée avant la confirmation, ou callback PawaPay jamais reçu),
  // on la ré-interroge auprès de PawaPay MAINTENANT. Un paiement abouti en
  // arrière-plan active l'abonnement + émet la licence sans callback entrant.
  if (PAWAPAY_API_TOKEN) {
    try {
      const pend = await pool.query(
        `SELECT id FROM payment_intents
          WHERE business_id=$1 AND provider='pawapay'
            AND status IN ('created','pending_customer','processing')
            AND created_at > now() - interval '90 days'
          ORDER BY created_at DESC LIMIT 1`,
        [dev.businessId],
      );
      if (pend.rows.length) await reconcilePawapayDeposit(String(pend.rows[0].id));
    } catch (e) {
      console.error("lazy payment reconcile", e);
    }
  }
  const { rows } = await pool.query(
    `SELECT s.status AS sub_status, s.plan_name, s.expires_at, s.price_fcfa,
            b.name AS business_name,
            l.id IS NOT NULL AS license_active,
            l.token AS license_token
       FROM businesses b
       LEFT JOIN LATERAL (
         SELECT status, plan_name, expires_at, price_fcfa FROM subscriptions
          WHERE business_id = b.id ORDER BY created_at DESC LIMIT 1
       ) s ON true
       LEFT JOIN LATERAL (
         SELECT id, token FROM licenses
          WHERE business_id = b.id AND revoked_at IS NULL AND expires_at > now()
          ORDER BY issued_at DESC LIMIT 1
       ) l ON true
      WHERE b.id = $1`,
    [dev.businessId],
  );
  const r = rows[0] || {};
  return ok(req, {
    businessId: dev.businessId,
    planName: r.plan_name || "—",
    subscriptionStatus: r.sub_status || "missing",
    licenseActive: !!r.license_active,
    expiresAt: r.expires_at ? new Date(r.expires_at).toISOString() : null,
    priceFcfa: r.price_fcfa != null ? Number(r.price_fcfa) : null,
    businessName: r.business_name || null,
    checkedAt: new Date().toISOString(),
    // Jeton Ed25519 brut : permet au client de vérifier la licence hors ligne
    // et d'ancrer sa grâce offline sur une preuve cryptographique.
    licenseToken: r.license_token || null,
  });
}

// ————————————————————————————————————————————————— Invitations cloud (multi-postes) ———
// Un second poste de la MÊME boutique rejoint via un code serveur à usage
// unique (pas de code d'activation consommé). Le quota d'appareils actifs est
// borné par plans.max_devices (audit déploiement, limite n°16).
function newInvitationCode(): string {
  const alpha = "BCDFGHJKLMNPQRSTVWXYZ23456789";
  const pick = (n: number) =>
    Array.from(crypto.randomBytes(n)).map((b) => alpha[b % alpha.length]).join("");
  return `INV-${pick(4)}-${pick(4)}`;
}
const INVITATION_ROLES = ["manager", "seller", "stockkeeper", "accountant"];

// { max_devices, active } — max_devices = plan du dernier abonnement, défaut 3.
async function deviceCapacity(businessId: string): Promise<{ max: number; active: number }> {
  const { rows } = await pool.query(
    `SELECT COALESCE((
              SELECT p.max_devices FROM subscriptions s
                JOIN plans p ON p.id = s.plan_id
               WHERE s.business_id = $1
               ORDER BY s.created_at DESC LIMIT 1
            ), 3) AS max_devices,
            (SELECT COUNT(*) FROM device_sync_tokens
              WHERE business_id = $1 AND revoked_at IS NULL) AS active_devices`,
    [businessId],
  );
  return {
    max: Number(rows[0]?.max_devices ?? 3),
    active: Number(rows[0]?.active_devices ?? 0),
  };
}

async function handleInvitationCreate(req: Request): Promise<Response> {
  const dev = await authDevice(req);
  if (!dev) return err(req, "Non autorisé.", 401);
  const body = await readJson(req);
  const role = String(body.role || "seller").trim().toLowerCase();
  if (!INVITATION_ROLES.includes(role)) return err(req, `Rôle invalide (${INVITATION_ROLES.join(" | ")}).`);
  const cap = await deviceCapacity(dev.businessId);
  if (cap.active >= cap.max) {
    return err(req, `Limite d'appareils atteinte (${cap.active}/${cap.max}). Révoquez un poste côté vendeur.`, 403);
  }
  const code = newInvitationCode();
  const { rows } = await pool.query(
    `INSERT INTO business_invitations (id, business_id, code, role, created_by, expires_at)
     VALUES ($1::uuid,$2,$3,$4,$5, now() + interval '7 days')
     RETURNING code, expires_at`,
    [crypto.randomUUID(), dev.businessId, code, role, String(body.createdBy || "").trim() || null],
  );
  return ok(req, {
    code: rows[0].code,
    role,
    expiresAt: new Date(rows[0].expires_at).toISOString(),
    devices: `${cap.active}/${cap.max}`,
  });
}

async function handleInvitationPeek(req: Request): Promise<Response> {
  const body = await readJson(req);
  const code = String(body.code || "").trim().toUpperCase();
  if (!/^INV-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(code)) return err(req, "Code d'invitation invalide.", 404);
  const { rows } = await pool.query(
    `SELECT bi.status, bi.role, bi.expires_at, b.id AS business_id, b.name, b.sector
       FROM business_invitations bi
       JOIN businesses b ON b.id = bi.business_id
      WHERE bi.code = $1`,
    [code],
  );
  if (!rows.length) return err(req, "Code d'invitation inconnu ou expiré.", 404);
  const r = rows[0];
  if (r.status !== "active" || new Date(r.expires_at).getTime() < Date.now()) {
    if (r.status === "active") {
      pool.query(`UPDATE business_invitations SET status='expired' WHERE code=$1`, [code]).catch(() => {});
    }
    return err(req, "Code d'invitation déjà utilisé ou expiré.", 409);
  }
  // Aucune donnée sensible : nom + secteur + rôle proposé.
  return ok(req, { businessId: r.business_id, businessName: r.name, sector: r.sector, role: r.role });
}

async function handleInvitationAccept(req: Request): Promise<Response> {
  const body = await readJson(req);
  const code = String(body.code || "").trim().toUpperCase();
  const deviceId = String(body.deviceId || "").trim();
  const fullName = String(body.fullName || "").trim();
  const phone = String(body.phone || "").trim();
  if (!/^INV-[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(code)) return err(req, "Code d'invitation invalide.", 404);
  if (!deviceId || deviceId.length > 128) return err(req, "deviceId requis.");
  if (fullName.length < 2 || fullName.length > 120) return err(req, "Nom complet requis (2 à 120 caractères).");

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const inv = await client.query(
      `SELECT bi.id, bi.business_id, bi.role, bi.expires_at, b.name, b.sector, b.phone, b.owner_name
         FROM business_invitations bi
         JOIN businesses b ON b.id = bi.business_id
        WHERE bi.code = $1 AND bi.status = 'active'
        FOR UPDATE`,
      [code],
    );
    if (!inv.rows.length) {
      await client.query("ROLLBACK");
      return err(req, "Code d'invitation inconnu ou déjà utilisé.", 404);
    }
    const row = inv.rows[0];
    if (new Date(row.expires_at).getTime() < Date.now()) {
      await client.query(`UPDATE business_invitations SET status='expired' WHERE id=$1::uuid`, [row.id]);
      await client.query("ROLLBACK");
      return err(req, "Code d'invitation expiré.", 409);
    }
    // Un seul jeton par appareil et par invitation : re-jointe du même
    // poste = ré-émission (l'invitation reste marquée utilisée pour l'audit).
    const existing = await client.query(
      `SELECT t.token_hash FROM device_sync_tokens t
        WHERE t.business_id=$1 AND t.device_id=$2 AND t.revoked_at IS NULL`,
      [row.business_id, deviceId],
    );
    if (existing.rows.length) {
      await client.query("ROLLBACK");
      return err(req, "Cet appareil est déjà rattaché à ce commerce.", 409);
    }
    const cap = await deviceCapacity(row.business_id);
    if (cap.active >= cap.max) {
      await client.query("ROLLBACK");
      return err(req, `Limite d'appareils atteinte (${cap.active}/${cap.max}).`, 403);
    }

    const userId = crypto.randomUUID();
    // users.phone est UNIQUE : si le numéro appartient déjà à un autre
    // compte, on rattache l'utilisateur sans téléphone plutôt qu'en erreur.
    let phoneValue: string | null = phone || null;
    if (phoneValue) {
      const dup = await client.query(`SELECT 1 FROM users WHERE lower(phone) = lower($1) LIMIT 1`, [phoneValue]);
      if (dup.rows.length) phoneValue = null;
    }
    await client.query(
      `INSERT INTO users (id, business_id, full_name, phone, role, status)
       VALUES ($1,$2,$3,$4,$5,'active')`,
      [userId, row.business_id, fullName, phoneValue, row.role],
    );
    const token = newSyncToken();
    await client.query(
      `INSERT INTO device_sync_tokens (id, business_id, device_id, token_hash)
       VALUES ($1::uuid,$2,$3,$4)`,
      [crypto.randomUUID(), row.business_id, deviceId, sha256hex(token)],
    );
    await client.query(
      `UPDATE business_invitations SET status='used', used_at=now(), used_device_id=$2 WHERE id=$1::uuid`,
      [row.id, deviceId],
    );
    await client.query("COMMIT");
    // Plan courant pour que le poste joint affiche tout de suite un cache
    // d'abonnement cohérent (best-effort : vide si aucun abonnement).
    const sub = await client.query(
      `SELECT plan_name, expires_at FROM subscriptions
        WHERE business_id=$1 ORDER BY created_at DESC LIMIT 1`,
      [row.business_id],
    ).catch(() => ({ rows: [] as any[] }));
    return ok(req, {
      businessId: row.business_id,
      userId,
      role: row.role,
      syncToken: token,
      syncEndpoint: new URL(req.url).origin + "/api/v1/sync/push",
      planName: sub.rows[0]?.plan_name || null,
      expiresAt: sub.rows[0]?.expires_at ? new Date(sub.rows[0].expires_at).toISOString() : null,
      business: {
        id: row.business_id,
        name: row.name,
        sector: row.sector,
        phone: row.phone,
        ownerName: row.owner_name,
      },
    });
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("invitation accept error", e);
    return err(req, "Échec de la jointure.", 500);
  } finally {
    client.release();
  }
}

async function handleSyncPush(req: Request): Promise<Response> {
  const dev = await authDevice(req);
  if (!dev) return err(req, "Non autorisé.", 401);
  const body = await readJson(req);
  const idemKey = req.headers.get("x-idempotency-key") || "";
  const items: any[] = Array.isArray(body.items)
    ? body.items
    : body.entityId
      ? [body]
      : [];
  if (!items.length) return ok(req, { accepted: 0 });

  const client = await pool.connect();
  let accepted = 0;
  try {
    // Idempotence batch : si déjà appliqué, on renvoie ok sans réécrire.
    if (idemKey) {
      const prior = await client.query(
        `SELECT id FROM sync_batches WHERE business_id=$1 AND idempotency_key=$2 AND status='applied'`,
        [dev.businessId, idemKey],
      );
      if (prior.rows.length) {
        return ok(req, { accepted: items.length, deduped: true });
      }
    }
    await client.query("BEGIN");
    if (idemKey) {
      await client.query(
        `INSERT INTO sync_batches (id, business_id, device_id, operation_count, status, idempotency_key)
         VALUES ($1,$2,$3,$4,'pending',$5)
         ON CONFLICT (business_id, idempotency_key) DO NOTHING`,
        [crypto.randomUUID(), dev.businessId, dev.deviceId, items.length, idemKey],
      );
    }
    for (const it of items) {
      const eventId = String(it.id || crypto.randomUUID());
      const entityType = String(it.entityType || "").trim();
      const entityId = String(it.entityId || "").trim();
      const operation = String(it.operation || "upsert").toLowerCase();
      if (!entityType || !entityId) continue;
      const payload = JSON.stringify(it.payload ?? {});
      const deleted = operation === "delete";
      const ins = await client.query(
        `INSERT INTO sync_events (id, business_id, entity_type, entity_id, operation, payload_json)
         VALUES ($1,$2,$3,$4,$5,$6::jsonb)
         ON CONFLICT (id) DO UPDATE SET operation = EXCLUDED.operation, payload_json = EXCLUDED.payload_json
         RETURNING server_seq`,
        [eventId, dev.businessId, entityType, entityId, operation, payload],
      );
      const seq = Number(ins.rows[0]?.server_seq ?? 0);
      await client.query(
        `INSERT INTO sync_entities (business_id, entity_type, entity_id, payload_json, deleted, device_seq, updated_at)
         VALUES ($1,$2,$3,$4::jsonb,$5,$6, now())
         ON CONFLICT (business_id, entity_type, entity_id)
         DO UPDATE SET payload_json = EXCLUDED.payload_json, deleted = EXCLUDED.deleted, device_seq = EXCLUDED.device_seq, updated_at = now()`,
        [dev.businessId, entityType, entityId, payload, deleted, seq],
      );
      accepted++;
    }
    if (idemKey) {
      await client.query(
        `UPDATE sync_batches SET status='applied' WHERE business_id=$1 AND idempotency_key=$2`,
        [dev.businessId, idemKey],
      );
    }
    await client.query("COMMIT");
    return ok(req, { accepted });
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    console.error("sync push error", e);
    return err(req, "Échec du push de synchronisation.", 500);
  } finally {
    client.release();
  }
}

async function handleSyncPull(req: Request): Promise<Response> {
  const dev = await authDevice(req);
  if (!dev) return err(req, "Non autorisé.", 401);
  const url = new URL(req.url);
  const businessId = url.searchParams.get("businessId") || dev.businessId;
  if (businessId !== dev.businessId) return err(req, "Business non autorisé.", 403); // S2
  const cursor = parseInt(url.searchParams.get("cursor") || "0", 10) || 0;
  const limit = Math.min(Math.max(parseInt(url.searchParams.get("limit") || "100", 10) || 100, 1), 500);
  const { rows } = await pool.query(
    `SELECT id, business_id, server_seq, entity_type, entity_id, operation, payload_json, created_at
       FROM sync_events
      WHERE business_id = $1 AND server_seq > $2
      ORDER BY server_seq ASC
      LIMIT $3`,
    [businessId, cursor, limit],
  );
  const items = rows.map((r) => ({
    serverSeq: Number(r.server_seq),
    businessId: r.business_id,
    entityType: r.entity_type,
    entityId: r.entity_id,
    operation: r.operation,
    payload: r.payload_json,
    deviceId: null,
    localCreatedAt: r.created_at ? new Date(r.created_at).toISOString() : null,
    entityVersion: Number(r.server_seq),
    updatedAt: r.created_at ? new Date(r.created_at).toISOString() : null,
  }));
  const nextCursor = items.length ? items[items.length - 1].serverSeq : cursor;
  return ok(req, { items, nextCursor, hasMore: rows.length === limit });
}

async function handleLogin(req: Request): Promise<Response> {
  const body = await readJson(req);
  const identifier = String(body.username || body.email || "").trim().toLowerCase();
  const password = String(body.password || "");
  if (!identifier || !password) return err(req, "Identifiants manquants.");
  const { rows } = await pool.query(
    `SELECT id, role, status, password_hash, token_version, full_name FROM staff_accounts
      WHERE lower(coalesce(email,'')) = $1 OR lower(coalesce(username,'')) = $1
      LIMIT 1`,
    [identifier],
  );
  if (!rows.length || rows[0].status !== "active" || !verifyPassword(password, rows[0].password_hash)) {
    return err(req, "Identifiants invalides.", 401);
  }
  const token = createAdminSessionToken(rows[0].id, rows[0].role || "commercial", Number(rows[0].token_version ?? 1));
  return ok(req, { token, role: rows[0].role, staffId: rows[0].id, full_name: rows[0].full_name || null });
}

async function handleLicenseIssue(req: Request): Promise<Response> {
  const session = await liveAdminSession(req);
  if (session instanceof Response) return session;
  if (!["super_admin", "supervisor"].includes(session.role))
    return err(req, "Rôle insuffisant.", 403);
  const body = await readJson(req);
  const businessId = String(body.businessId || "").trim();
  const plan = String(body.plan || "PRO").trim();
  const days = Math.max(1, Math.min(730, parseInt(body.days || "30", 10) || 30));
  if (!businessId) return err(req, "businessId requis.");
  if (!licensePrivateKey()) return err(req, "Clef de signature non configurée.", 500);
  const biz = await pool.query(`SELECT 1 FROM businesses WHERE id = $1`, [businessId]);
  if (!biz.rows.length) return err(req, "Entreprise inconnu.", 404);

  const now = Math.floor(Date.now() / 1000);
  const claims: LicenseClaims = {
    businessId,
    plan,
    issuedAt: now,
    expiresAt: now + days * 86400,
    nonce: crypto.randomBytes(16).toString("hex"),
    keyId: LICENSE_KEY_ID,
    graceDays: 7,
  };
  const token = signLicense(claims)!;
  await pool.query(
    `INSERT INTO licenses (business_id, plan, token_hash, token, key_id, expires_at, nonce)
     VALUES ($1,$2,$3,$4,$5, to_timestamp($6), $7)`,
    [businessId, plan, sha256hex(token), token, LICENSE_KEY_ID, claims.expiresAt, claims.nonce],
  );
  // Active/étend l'abonnement associé.
  await pool.query(
    `UPDATE subscriptions SET status='active', expires_at = to_timestamp($2), updated_at=now()
      WHERE business_id=$1`,
    [businessId, claims.expiresAt],
  ).catch(() => {});
  return ok(req, { token, keyId: LICENSE_KEY_ID, expiresAt: new Date(claims.expiresAt * 1000).toISOString() });
}

async function handlePaymentWebhook(req: Request): Promise<Response> {
  const raw = await req.text();
  const sig = req.headers.get("x-webhook-signature") || req.headers.get("x-signature") || "";
  if (!PAYMENT_WEBHOOK_SECRET) return err(req, "Webhook non configuré.", 501);
  if (!sig || !safeEqual(sig, hmacHex(PAYMENT_WEBHOOK_SECRET, raw))) {
    return err(req, "Signature invalide.", 401);
  }
  let payload: any = {};
  try { payload = JSON.parse(raw); } catch {}
  const ref = String(payload.providerReference || payload.reference || payload.transaction_id || "");
  const businessId = String(payload.businessId || "");
  const plan = String(payload.plan || "PRO");
  const status = String(payload.status || "succeeded").toLowerCase();
  if (!ref) return err(req, "Référence manquante.");
  // Idempotent : journalise l'événement signature-valide.
  await pool.query(
    `INSERT INTO payment_webhook_events (id, provider, provider_reference, event_type, payload, signature_valid, processed)
     VALUES ($1,$2,$3,$4,$5::jsonb, true, true) ON CONFLICT DO NOTHING`,
    [crypto.randomUUID(), String(payload.provider || "aggregator"), ref, String(payload.event || "payment"), raw],
  ).catch(() => {});
  if (status === "succeeded" || status === "paid" || status === "success") {
    await pool.query(
      `UPDATE payment_intents SET status='succeeded', updated_at=now() WHERE provider_reference=$1`,
      [ref],
    ).catch(() => {});
    if (businessId) {
      await pool.query(
        `UPDATE subscriptions SET status='active', plan_name=$2, updated_at=now()
          WHERE business_id=$1`,
        [businessId, plan],
      ).catch(() => {});
    }
  }
  return ok(req, { received: true });
}

// ————————————————————————————————————————————————————————— PawaPay — dépôt / statut / callback ———
// Modèle PUSH PawaPay : la demande arrive sur le téléphone du client, qui la
// valide avec SON code secret opérateur. Le PIN/OTP mobile ne transite JAMAIS
// par Lynkstor. Le corps du callback n'est jamais cru sur parole : chaque
// réconciliation ré-interroge l'API Check Status de PawaPay (source de vérité).

async function pawapay(
  path: string,
  init?: { method?: string; body?: unknown },
): Promise<{ httpStatus: number; json: any; networkOk: boolean }> {
  try {
    const res = await fetch(PAWAPAY_API_BASE + path, {
      method: init?.method || "GET",
      headers: {
        Authorization: `Bearer ${PAWAPAY_API_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: init?.body !== undefined ? JSON.stringify(init.body) : undefined,
      signal: AbortSignal.timeout(20000),
    });
    let json: any = null;
    try {
      json = await res.json();
    } catch {}
    return { httpStatus: res.status, json, networkOk: true };
  } catch (e) {
    console.error("pawapay fetch error", String(e));
    return { httpStatus: 0, json: null, networkOk: false };
  }
}

// Normalise un MSISDN au format PawaPay : chiffres seuls, indicatif pays inclus.
function normalizeMsisdn(raw: string): string | null {
  let d = String(raw || "").replace(/\D/g, "");
  if (d.startsWith("00")) d = d.slice(2);
  if (!d) return null;
  const national = PAWAPAY_DIAL_CODE.length + 9; // Cameroun : 237 + 9 chiffres.
  if (d.startsWith(PAWAPAY_DIAL_CODE) && d.length >= national - 1 && d.length <= national + 1) return d;
  if (d.length === 9 && !d.startsWith("0")) return PAWAPAY_DIAL_CODE + d;
  return null;
}

function statementNote(planName: string): string {
  // 4 à 22 caractères alphanumériques/espaces (contrat PawaPay), visible sur le SMS client.
  const s = `LYNKSTOR ${planName}`.toUpperCase().replace(/[^A-Z0-9 ]/g, "").trim().slice(0, 22);
  return s.length >= 4 ? s : "LYNKSTOR";
}

// Active (ou étend) l'abonnement + émet la licence Ed25519 associée.
// Idempotent : appelé uniquement par le gagnant de la transition -> succeeded.
async function activatePaidPlan(
  businessId: string,
  planName: string,
  planId: string | null,
  months: number,
  amountFcfa: number,
): Promise<{ licenseToken: string | null; expiresAt: string | null }> {
  const m = Math.max(1, Math.min(24, Math.round(months) || 1));
  const days = m * 30;
  const nowSec = Math.floor(Date.now() / 1000);
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    let expiresIso: string | null = null;
    const upd = await client.query(
      `UPDATE subscriptions
          SET status='active', plan_id=coalesce($2, plan_id), plan_name=$3,
              expires_at = GREATEST(COALESCE(expires_at, now()), now()) + make_interval(months => ${m}),
              updated_at = now()
        WHERE business_id = $1
      RETURNING expires_at`,
      [businessId, planId, planName],
    );
    if (upd.rows.length) {
      expiresIso = new Date(upd.rows[0].expires_at).toISOString();
    } else {
      const ins = await client.query(
        `INSERT INTO subscriptions (id, business_id, plan_id, plan_name, status, price_fcfa, started_at, expires_at)
         VALUES ($1,$2,$3,$4,'active',$5, now(), now() + make_interval(days => $6::int))
         RETURNING expires_at`,
        [crypto.randomUUID(), businessId, planId, planName, amountFcfa, days],
      );
      if (ins.rows.length) expiresIso = new Date(ins.rows[0].expires_at).toISOString();
    }
    // La licence couvre au moins la période payée, et jamais moins que l'expiration
    // déjà acquise (renewal anticipé = jours conservés).
    let licenseToken: string | null = null;
    if (licensePrivateKey()) {
      const subExpiresSec = expiresIso ? Math.floor(new Date(expiresIso).getTime() / 1000) : 0;
      const claims: LicenseClaims = {
        businessId,
        plan: planName,
        issuedAt: nowSec,
        expiresAt: Math.max(nowSec + days * 86400, subExpiresSec),
        nonce: crypto.randomBytes(16).toString("hex"),
        keyId: LICENSE_KEY_ID,
        graceDays: 7,
      };
      licenseToken = signLicense(claims);
      if (licenseToken) {
        await client.query(
          `INSERT INTO licenses (business_id, plan, token_hash, token, key_id, expires_at, nonce)
           VALUES ($1,$2,$3,$4,$5, to_timestamp($6), $7)`,
          [businessId, planName, sha256hex(licenseToken), licenseToken, LICENSE_KEY_ID, claims.expiresAt, claims.nonce],
        );
      }
    }
    await client.query("COMMIT");
    return { licenseToken, expiresAt: expiresIso };
  } catch (e) {
    await client.query("ROLLBACK").catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

// Réconciliation d'un dépôt : interrogent PawaPay (jamais le corps webhook),
// puis marquent succeeded en CAS (compare-and-set) avant activation.
async function reconcilePawapayDeposit(depositId: string): Promise<{
  found: boolean;
  status: string;
  failure?: string;
}> {
  const { rows } = await pool.query(`SELECT * FROM payment_intents WHERE id = $1`, [depositId]);
  if (!rows.length) return { found: false, status: "unknown" };
  const intent = rows[0];
  if (intent.status === "succeeded") return { found: true, status: "succeeded" };
  if (intent.status === "failed" || intent.status === "expired") return { found: true, status: intent.status };
  if (!PAWAPAY_API_TOKEN) return { found: true, status: intent.status };

  const { httpStatus, json, networkOk } = await pawapay(`/deposits/${encodeURIComponent(depositId)}`);
  if (!networkOk || httpStatus === 500) {
    // Erreur réseau PawaPay : on ne conclut PAS (rester pending, re-proché plus tard).
    return { found: true, status: intent.status };
  }
  const dep: any = Array.isArray(json) ? json[0] : json;
  if (httpStatus === 404 || (httpStatus === 200 && Array.isArray(json) && json.length === 0)) {
    const ageMin = (Date.now() - new Date(intent.created_at).getTime()) / 60000;
    if (ageMin > 10) {
      await pool.query(
        `UPDATE payment_intents SET status='failed', updated_at=now() WHERE id=$1 AND status NOT IN ('succeeded','failed')`,
        [depositId],
      );
      return { found: true, status: "failed", failure: "Dépôt inconnu de PawaPay." };
    }
    return { found: true, status: "created" };
  }
  if (httpStatus === 401 || httpStatus === 403) {
    console.error("pawapay auth failure", httpStatus);
    return { found: true, status: intent.status, failure: "auth" };
  }

  const s = String(dep?.status || "").toUpperCase();
  if (s === "COMPLETED") {
    const want = Number(intent.amount_fcfa);
    const got = Number(dep?.depositedAmount ?? dep?.requestedAmount ?? want);
    if (Number.isFinite(got) && got !== want) {
      // Écart de montant : on n'active jamais, on signale pour audit manuel.
      await pool.query(
        `UPDATE payment_intents SET status='processing', updated_at=now() WHERE id=$1 AND status='pending_customer'`,
        [depositId],
      );
      return { found: true, status: "processing", failure: `écart de montant (${got} ≠ ${want})` };
    }
    const marked = await pool.query(
      `UPDATE payment_intents SET status='succeeded', updated_at=now() WHERE id=$1 AND status <> 'succeeded' RETURNING id`,
      [depositId],
    );
    if (marked.rows.length) {
      const plan = intent.plan_id
        ? await pool.query(`SELECT name, billing_period FROM plans WHERE id = $1`, [intent.plan_id])
        : { rows: [] as any[] };
      const months = MONTHS_BY_BILLING_PERIOD[String(plan.rows[0]?.billing_period || "monthly")] ?? 1;
      await activatePaidPlan(
        intent.business_id,
        plan.rows[0]?.name || intent.plan_id || "STARTER",
        intent.plan_id,
        months,
        want,
      );
    }
    return { found: true, status: "succeeded" };
  }
  if (s === "FAILED" || s === "REJECTED" || s === "CANCELLED" || s === "EXPIRED") {
    await pool.query(
      `UPDATE payment_intents SET status='failed', updated_at=now() WHERE id=$1 AND status NOT IN ('succeeded','failed')`,
      [depositId],
    );
    const code = dep?.failureReason?.failureCode || s;
    return { found: true, status: "failed", failure: String(code) };
  }
  const next = s === "SUBMITTED" ? "processing" : "pending_customer";
  await pool.query(
    `UPDATE payment_intents SET status=$2, updated_at=now() WHERE id=$1 AND status NOT IN ('succeeded','failed')`,
    [depositId, next],
  );
  return { found: true, status: next };
}

async function handlePaymentInitiate(req: Request): Promise<Response> {
  const dev = await authDevice(req);
  if (!dev) return err(req, "Non autorisé.", 401);
  if (!PAWAPAY_API_TOKEN) return err(req, "Paiement Mobile Money non activé pour l'instant.", 503);

  const body = await readJson(req);
  const channel = String(body.channel || "").trim().toLowerCase();
  const correspondent = PAWAPAY_CORRESPONDENTS[channel];
  if (!correspondent) return err(req, "Canal invalide (orange_money | mtn_momo).");
  const phone = normalizeMsisdn(String(body.phone || ""));
  if (!phone) return err(req, `Numéro invalide. Format attendu : +${PAWAPAY_DIAL_CODE} 6XXXXXXXX.`);

  // Montant + forfait résolus CÔTÉ SERVEUR (le client ne fixe jamais le prix).
  const requested = String(body.planId || "").trim().toUpperCase();
  let plan: any = null;
  if (requested) {
    const p = await pool.query(`SELECT id, name, price_fcfa, billing_period FROM plans WHERE id=$1 AND is_active`, [requested]);
    plan = p.rows[0];
    if (!plan) return err(req, "Forfait inconnu.", 404);
  }
  if (!plan) {
    const s = await pool.query(
      `SELECT plan_id, plan_name, price_fcfa FROM subscriptions WHERE business_id=$1 ORDER BY created_at DESC LIMIT 1`,
      [dev.businessId],
    );
    const sub = s.rows[0];
    if (sub?.plan_id) {
      const p = await pool.query(`SELECT id, name, price_fcfa, billing_period FROM plans WHERE id=$1 AND is_active`, [String(sub.plan_id).toUpperCase()]);
      plan = p.rows[0];
    }
    if (!plan) plan = { id: null, name: sub?.plan_name || "STARTER", price_fcfa: sub?.price_fcfa ?? 0, billing_period: "monthly" };
  }
  const amount = Math.round(Number(plan.price_fcfa || 0));
  if (!Number.isFinite(amount) || amount < PAWAPAY_DEPOSIT_MIN)
    return err(req, "Aucun tarif en ligne pour ce compte. Contactez votre commercial Lynkstor.");

  const intentId = crypto.randomUUID(); // = depositId PawaPay (UUID v4, 36 chars) : clé d'idempotence.
  await pool.query(
    `INSERT INTO payment_intents
       (id, business_id, plan_id, provider, channel, amount_fcfa, currency, status, provider_reference, customer_phone)
     VALUES ($1,$2,$3,'pawapay',$4,$5,$6,'created',$1,$7)`,
    [intentId, dev.businessId, plan.id || null, channel, amount, PAWAPAY_CURRENCY, phone],
  );

  const { httpStatus, json, networkOk } = await pawapay("/deposits", {
    method: "POST",
    body: {
      depositId: intentId,
      amount: String(amount),
      currency: PAWAPAY_CURRENCY,
      country: PAWAPAY_COUNTRY,
      correspondent,
      payer: { type: "MSISDN", address: { value: phone } },
      customerTimestamp: new Date().toISOString(),
      statementDescription: statementNote(String(plan.name || "")),
      metadata: [
        { fieldName: "app", fieldValue: "Lynkstor" },
        { fieldName: "businessId", fieldValue: dev.businessId },
      ],
    },
  });

  if (networkOk && httpStatus === 200 && (json?.status === "ACCEPTED" || json?.status === "DUPLICATE_IGNORED")) {
    await pool.query(`UPDATE payment_intents SET status='pending_customer', updated_at=now() WHERE id=$1`, [intentId]);
    return ok(
      req,
      { intentId, status: "pending_customer", amount, currency: PAWAPAY_CURRENCY },
      "Une demande de paiement a été envoyée sur votre téléphone. Confirmez-la avec votre code secret Mobile Money.",
    );
  }
  if (networkOk && httpStatus === 200 && json?.status === "REJECTED") {
    const reason = json?.rejectionReason?.rejectionMessage || json?.rejectionReason?.rejectionCode || "demande rejetée";
    await pool.query(`UPDATE payment_intents SET status='failed', updated_at=now() WHERE id=$1`, [intentId]);
    return ok(req, { intentId, status: "failed", rejection: json?.rejectionReason || null }, `Paiement refusé : ${reason}`);
  }
  // Réseau/5xx : la demande a peut-être quand même été reçue par PawaPay.
  // On NE conclut pas en échec — le polling /callback tranchera via Check Status.
  console.error("pawapay initiate inconclusive", httpStatus, JSON.stringify(json ?? {}).slice(0, 300));
  return err(req, "PawaPay momentanément injoignable. Réessayez dans quelques instants.", 502);
}

async function handlePaymentStatus(req: Request, intentId: string): Promise<Response> {
  const dev = await authDevice(req);
  if (!dev) return err(req, "Non autorisé.", 401);
  const { rows } = await pool.query(
    `SELECT id, status, amount_fcfa FROM payment_intents WHERE id=$1 AND business_id=$2`,
    [intentId, dev.businessId],
  );
  if (!rows.length) return err(req, "Paiement introuvable.", 404);
  let status = String(rows[0].status);
  if (status !== "succeeded" && status !== "failed" && status !== "expired") {
    status = (await reconcilePawapayDeposit(intentId)).status;
  }
  return ok(req, { intentId, status, amount: Number(rows[0].amount_fcfa) });
}

// Callback PawaPay (URL configurée dans le dashboard PawaPay). Corps JAMAIS cru :
// il ne sert qu'à réveiller une réconciliation qui re-interroge l'API PawaPay.
async function handlePawapayWebhook(req: Request): Promise<Response> {
  const raw = await req.text();
  let payload: any = {};
  try {
    payload = JSON.parse(raw);
  } catch {
    return ok(req, { received: false });
  }
  const dep = Array.isArray(payload) ? payload[0] : payload;
  const depositId = String(dep?.depositId || dep?.uniqueRequestIdentifier || dep?.transactionId || "").trim();
  const eventType = String(dep?.status || "unknown");
  if (!depositId) return ok(req, { received: false });
  await pool
    .query(
      `INSERT INTO payment_webhook_events (id, provider, provider_reference, event_type, payload, signature_valid, processed)
       VALUES ($1,'pawapay',$2,$3,$4::jsonb, false, true) ON CONFLICT DO NOTHING`,
      [crypto.randomUUID(), depositId, eventType, raw],
    )
    .catch(() => {});
  await reconcilePawapayDeposit(depositId).catch((e) => console.error("pawapay webhook reconcile", e));
  return ok(req, { received: true });
}

// ————————————————————————————————————————————————————— Routes admin (dashboard) ———
// KPIs réels agrégés depuis Neon. `totalSalesFcfa` somme la dernière valeur
// synchronisée par appareil (`distinct on`), jamais les événements de sync.
async function handleAdminStats(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const one = async (sql: string) => {
    try {
      const { rows } = await pool.query(sql);
      return rows[0] || {};
    } catch {
      return {};
    }
  };
  const [biz, users, subs, activeLic, revokedLic, availCodes, totalCodes, usedCodes, fieldColl, sales, devices, events] =
    await Promise.all([
      one(`SELECT count(*)::int AS n FROM businesses`),
      one(`SELECT count(*)::int AS n FROM users`),
      one(`SELECT count(*)::int AS n FROM subscriptions WHERE status IN ('active','trial')`),
      one(`SELECT count(*)::int AS n FROM licenses WHERE revoked_at IS NULL AND expires_at > now()`),
      one(`SELECT count(*)::int AS n FROM licenses WHERE revoked_at IS NOT NULL`),
      one(`SELECT count(*)::int AS n FROM registration_codes WHERE status = 'available'`),
      one(`SELECT count(*)::int AS n FROM registration_codes`),
      one(`SELECT count(*)::int AS n FROM registration_codes WHERE status = 'used'`),
      one(`SELECT COALESCE(sum(amount_collected_fcfa), 0)::bigint AS n FROM field_activities`),
      one(`
        SELECT COALESCE(sum((payload_json ->> 'totalAmount')::numeric), 0)::bigint AS n
          FROM (
            SELECT distinct on (business_id, entity_id) payload_json
              FROM sync_events WHERE entity_type = 'sale'
          ) s
      `),
      one(`SELECT count(*)::int AS n FROM device_sync_tokens WHERE revoked_at IS NULL`),
      one(`SELECT count(*)::int AS n FROM sync_events`),
    ]);
  return ok(req, {
    totalBusinesses: biz.n ?? 0,
    totalUsers: users.n ?? 0,
    activeSubscriptions: subs.n ?? 0,
    activeLicenses: activeLic.n ?? 0,
    revokedLicenses: revokedLic.n ?? 0,
    availableCodes: availCodes.n ?? 0,
    totalCodes: totalCodes.n ?? 0,
    usedCodes: usedCodes.n ?? 0,
    totalFieldCollectionsFcfa: fieldColl.n ?? 0,
    totalSalesFcfa: sales.n ?? 0,
    activeDevices: devices.n ?? 0,
    totalSyncEvents: events.n ?? 0,
  });
}

async function handleAdminBusinesses(req: Request, url: URL): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const q = `%${(url.searchParams.get("q") || "").trim()}%`;
  const { rows } = await pool.query(
    `SELECT b.id, b.name, b.sector, b.phone, b.owner_name, b.status,
            b.latitude, b.longitude, b.created_at,
            s.plan_name, s.status AS sub_status, s.expires_at,
            l.expires_at AS license_expires_at,
            (SELECT count(*) FROM device_sync_tokens d WHERE d.business_id = b.id AND d.revoked_at IS NULL) AS devices
       FROM businesses b
       LEFT JOIN LATERAL (
         SELECT plan_name, status, expires_at FROM subscriptions WHERE business_id = b.id
          ORDER BY created_at DESC LIMIT 1) s ON true
       LEFT JOIN LATERAL (
         SELECT expires_at FROM licenses WHERE business_id = b.id AND revoked_at IS NULL
          ORDER BY issued_at DESC LIMIT 1) l ON true
      WHERE b.name ILIKE $1 OR b.owner_name ILIKE $1 OR b.phone ILIKE $1 OR b.id ILIKE $1
      ORDER BY b.created_at DESC
      LIMIT 200`,
    [q],
  );
  return ok(req, rows);
}

async function handleAdminCodes(req: Request, url: URL): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const status = url.searchParams.get("status") || "";
  const { rows } = await pool.query(
    `SELECT rc.id, rc.code, rc.business_name, rc.owner_phone, rc.status, rc.assigned_staff,
            rc.plan_id, rc.used_by_business, rc.created_at, rc.used_at,
            p.name AS plan_name, sa.full_name AS assigned_staff_name,
            b.name AS used_by_business_name
       FROM registration_codes rc
       LEFT JOIN plans p ON p.id = rc.plan_id
       LEFT JOIN staff_accounts sa ON sa.id = rc.assigned_staff
       LEFT JOIN businesses b ON b.id = rc.used_by_business
      WHERE ($1 = '' OR rc.status = $1)
      ORDER BY rc.created_at DESC
      LIMIT 500`,
    [status],
  );
  return ok(req, rows);
}

async function handleAdminCodesGenerate(req: Request): Promise<Response> {
  const guard = await requireAdmin(req, true);
  if (isAdminResponse(guard)) return guard;
  const body = await readJson(req);
  let planId = String(body.planId || "").trim() || null;
  if (!planId) {
    const { rows } = await pool.query(`SELECT id FROM plans WHERE is_active = true ORDER BY price_fcfa LIMIT 1`);
    planId = rows[0]?.id ?? null;
  }
  if (!planId) return err(req, "Aucun plan actif : crée d'abord un plan.", 400);
  const count = Math.max(1, Math.min(50, parseInt(body.count || "1", 10) || 1));
  const assignedStaff = String(body.assignedStaff || guard.sub || "").trim() || null;
  const codes: string[] = [];
  for (let i = 0; i < count; i++) {
    const code = newActivationCode();
    const res = await pool.query(
      `INSERT INTO registration_codes (id, code, business_name, owner_phone, assigned_staff, plan_id, status)
       VALUES ($1,$2,$3::text,$4::text,$5::text,$6::uuid,'available')`,
      [crypto.randomUUID(), code,
       String(body.businessName || "").trim() || null,
       String(body.ownerPhone || "").trim() || null,
       assignedStaff, planId],
    );
    if (res.rowCount) codes.push(code);
  }
  return ok(req, { count: codes.length, codes }, `${codes.length} code(s) généré(s).`);
}

async function handleAdminCodesPreview(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const body = await readJson(req);
  const code = String(body.code || "").trim().toUpperCase();
  if (!code) return err(req, "code requis.");
  const { rows } = await pool.query(
    `SELECT rc.code, rc.status, rc.business_name, rc.owner_phone, rc.used_by_business,
            rc.created_at, rc.used_at, p.name AS plan_name
       FROM registration_codes rc
       LEFT JOIN plans p ON p.id = rc.plan_id
      WHERE rc.code = $1`,
    [code],
  );
  if (!rows.length) return err(req, "Code inconnu.", 404);
  return ok(req, rows[0]);
}

async function handleAdminCodesRevoke(req: Request): Promise<Response> {
  const guard = await requireAdmin(req, true);
  if (isAdminResponse(guard)) return guard;
  const body = await readJson(req);
  const code = String(body.code || "").trim().toUpperCase();
  if (!code) return err(req, "Code requis.");
  const { rowCount } = await pool.query(
    `UPDATE registration_codes SET status = 'void' WHERE code = $1 AND status = 'available'`,
    [code],
  );
  if (!rowCount) return err(req, "Code introuvable ou déjà utilisé/révoqué.", 404);
  return ok(req, { code }, `Code ${code} révoqué.`);
}

async function handleAdminStaff(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const { rows } = await pool.query(
    `SELECT s.id, s.username, s.full_name, s.email, s.phone, s.role, s.status,
            s.current_lat, s.current_lng, s.last_ping_at, s.created_at,
            COALESCE((SELECT sum(amount_collected_fcfa) FROM field_activities fa WHERE fa.staff_id = s.id), 0) AS total_collected_fcfa,
            COALESCE((SELECT count(*) FROM field_activities fa WHERE fa.staff_id = s.id), 0) AS total_activities,
            COALESCE((SELECT count(*) FROM registration_codes rc WHERE rc.assigned_staff = s.id AND rc.status = 'available'), 0) AS available_codes_count
       FROM staff_accounts s
      ORDER BY s.created_at DESC`,
  );
  return ok(req, rows); // password_hash volontairement absent
}

async function handleAdminStaffCreate(req: Request): Promise<Response> {
  const guard = await requireAdmin(req, true);
  if (isAdminResponse(guard)) return guard;
  const body = await readJson(req);
  const fullName = String(body.full_name || body.fullName || "").trim();
  const username = String(body.username || "").trim().toLowerCase();
  const password = String(body.password || "");
  const email = String(body.email || "").trim() || null;
  const phone = String(body.phone || "").trim() || null;
  const role = String(body.role || "commercial").trim();
  if (!fullName || !username) return err(req, "full_name et username requis.");
  if (!/^[a-z0-9._-]{3,32}$/.test(username)) return err(req, "username invalide (3-32, minuscules, sans espaces).");
  if (password.length < 12) return err(req, "password trop court (12 caractères minimum).");
  const allowed = ["super_admin", "supervisor", "commercial", "manager", "caissier"];
  if (!allowed.includes(role)) return err(req, `role invalide (${allowed.join(" | ")}).`);
  // Un commercial ne peut JAMAIS être promu administrateur via cette route.
  if (guard.role !== "super_admin" && ["super_admin", "supervisor"].includes(role))
    return err(req, "Seul un super_admin peut créer un compte admin.", 403);
  const dup = await pool.query(
    `SELECT 1 FROM staff_accounts WHERE lower(coalesce(username,'')) = $1::text OR ($2::text IS NOT NULL AND lower(coalesce(email,'')) = $2::text) LIMIT 1`,
    [username, email],
  );
  if (dup.rows.length) return err(req, "Ce username ou cet email existe déjà.", 409);
  const id = String(body.id || "").trim() || crypto.randomUUID();
  await pool.query(
    `INSERT INTO staff_accounts (id, username, password_hash, full_name, email, phone, role, status)
     VALUES ($1,$2,$3,$4,$5::text,$6::text,$7::text,'active')`,
    [id, username, hashPassword(password), fullName, email, phone, role],
  );
  return ok(req, { id, username, role }, `Compte ${role} créé (${username}).`);
}

async function handleAdminStaffDelete(req: Request): Promise<Response> {
  const guard = await requireAdmin(req, true);
  if (isAdminResponse(guard)) return guard;
  if (guard.role !== "super_admin") return err(req, "Réservé aux super_admin.", 403);
  const body = await readJson(req);
  const id = String(body.id || "").trim();
  if (!id) return err(req, "id requis.");
  if (id === guard.sub) return err(req, "Impossible de supprimer son propre compte.");
  const { rowCount } = await pool.query(`DELETE FROM staff_accounts WHERE id = $1`, [id]);
  if (!rowCount) return err(req, "Compte staff introuvable.", 404);
  return ok(req, { id }, "Compte supprimé.");
}

// Révocation de sessions staff : suspendre/réactiver un compte, changer son
// rôle ou réinitialiser son mot de passe incrémente token_version — toutes les
// sessions HMAC déjà émises pour ce compte meurent à la requête suivante.
// La suppression du compte révoque aussi (la ligne n'existe plus).
async function handleAdminStaffUpdate(req: Request): Promise<Response> {
  const guard = await requireAdmin(req, true);
  if (isAdminResponse(guard)) return guard;
  if (guard.role !== "super_admin") return err(req, "Réservé aux super_admin.", 403);
  const body = await readJson(req);
  const id = String(body.id || "").trim();
  if (!id) return err(req, "id requis.");
  const status = body.status === undefined ? null : String(body.status).trim();
  const role = body.role === undefined ? null : String(body.role).trim();
  const password = body.password === undefined ? null : String(body.password);
  if (!status && !role && !password) return err(req, "Rien à modifier (status, role ou password).");
  if (status && !["active", "disabled"].includes(status))
    return err(req, "status invalide (active | disabled).");
  if (role && !["super_admin", "supervisor", "commercial"].includes(role))
    return err(req, "role invalide (super_admin | supervisor | commercial).");
  if (password !== null && password.length < 12)
    return err(req, "password trop court (12 caractères minimum).");
  // Anti-lockout : on ne peut pas se désactiver ni se rétrograder soi-même.
  if (id === guard.sub && (status === "disabled" || (role && role !== guard.role)))
    return err(req, "Impossible de désactiver ou rétrograder son propre compte.");
  const sets: string[] = [];
  const params: unknown[] = [];
  if (status) { params.push(status); sets.push(`status = $${params.length}::text`); }
  if (role) { params.push(role); sets.push(`role = $${params.length}::text`); }
  if (password) { params.push(hashPassword(password)); sets.push(`password_hash = $${params.length}::text`); }
  params.push(id);
  const { rows } = await pool.query(
    `UPDATE staff_accounts SET ${sets.join(", ")}, token_version = token_version + 1
      WHERE id = $${params.length}
      RETURNING id, role, status, token_version`,
    params,
  );
  if (!rows.length) return err(req, "Compte staff introuvable.", 404);
  const self = id === guard.sub;
  const msg = password && self
    ? "Mot de passe changé : toutes les sessions (y compris la vôtre) sont révoquées."
    : "Compte mis à jour : sessions existantes révoquées.";
  return ok(req, { id: rows[0].id, role: rows[0].role, status: rows[0].status, tokenVersion: rows[0].token_version }, msg);
}

async function handleAdminLicenseRevoke(req: Request): Promise<Response> {
  const guard = await requireAdmin(req, true);
  if (isAdminResponse(guard)) return guard;
  if (guard.role !== "super_admin") return err(req, "Réservé aux super_admin.", 403);
  const body = await readJson(req);
  const businessId = String(body.businessId || "").trim();
  if (!businessId) return err(req, "businessId requis.");
  const { rowCount } = await pool.query(
    `UPDATE licenses SET revoked_at = now() WHERE business_id = $1 AND revoked_at IS NULL`,
    [businessId],
  );
  if (!rowCount) return err(req, "Aucune licence active pour cette entreprise.", 404);
  return ok(req, { businessId, revoked: rowCount }, `${rowCount} licence(s) révoquée(s).`);
}

// Enveloppe du dashboard admin (front existant qui teste `status === 'success'`).
const success = (req: Request, data: unknown) => json(req, { status: "success", data });

async function handleAdminSubscriptions(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const { rows } = await pool.query(
    `SELECT s.id, s.business_id, s.plan_name, s.status, s.price_fcfa, s.started_at, s.expires_at, s.created_at,
            b.name AS business_name, b.owner_name, b.phone
       FROM subscriptions s
       JOIN businesses b ON b.id = s.business_id
      ORDER BY s.created_at DESC
      LIMIT 500`,
  );
  return success(req, rows);
}

async function handleAdminFieldActivities(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const { rows } = await pool.query(
    `SELECT fa.id, fa.staff_id, fa.business_id, fa.activity_type, fa.amount_collected_fcfa,
            fa.notes, fa.created_at, sa.full_name AS staff_name, b.name AS business_name
       FROM field_activities fa
       JOIN staff_accounts sa ON sa.id = fa.staff_id
       JOIN businesses b ON b.id = fa.business_id
      ORDER BY fa.created_at DESC
      LIMIT 50`,
  );
  return success(req, rows);
}

async function handleAdminMapData(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const [bizRes, staffRes] = await Promise.all([
    pool.query(
      `SELECT b.id, b.name, b.owner_name, b.phone, b.latitude, b.longitude,
              s.plan_name, s.status AS sub_status, s.expires_at
         FROM businesses b
         LEFT JOIN LATERAL (
           SELECT plan_name, status, expires_at FROM subscriptions WHERE business_id = b.id
            ORDER BY created_at DESC LIMIT 1) s ON true`,
    ),
    pool.query(
      `SELECT id, full_name, phone, role, status, current_lat, current_lng, last_ping_at
         FROM staff_accounts WHERE role = 'commercial'`,
    ),
  ]);
  return success(req, { businesses: bizRes.rows, commercials: staffRes.rows });
}

async function handleAdminUsers(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const { rows } = await pool.query(
    `SELECT u.id, u.full_name, u.phone, u.role, u.status, u.created_at,
            b.name AS business_name, b.sector, s.plan_name, s.status AS sub_status
       FROM users u
       LEFT JOIN businesses b ON b.id = u.business_id
       LEFT JOIN LATERAL (
         SELECT plan_name, status FROM subscriptions WHERE business_id = u.business_id
          ORDER BY created_at DESC LIMIT 1) s ON true
      ORDER BY u.created_at DESC
      LIMIT 500`,
  );
  return success(req, rows);
}

async function handleAdminSyncLogs(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const { rows } = await pool.query(
    `SELECT se.id, se.business_id, se.entity_type, se.entity_id, se.operation, se.created_at,
            b.name AS business_name
       FROM sync_events se
       LEFT JOIN businesses b ON b.id = se.business_id
      ORDER BY se.created_at DESC
      LIMIT 50`,
  );
  return success(req, rows);
}

// Ping GPS d'un agent commercial (terminal terrain). Public : sans session,
// comme /license/issue n'est pas requis ici ; la position alimente la carte.
async function handleCommercialPing(req: Request): Promise<Response> {
  const body = await readJson(req);
  const staffId = String(body.staff_id || "").trim();
  const lat = Number(body.latitude);
  const lng = Number(body.longitude);
  if (!staffId || !Number.isFinite(lat) || !Number.isFinite(lng))
    return err(req, "staff_id, latitude, longitude requis.");
  const { rowCount } = await pool.query(
    `UPDATE staff_accounts SET current_lat = $1::numeric, current_lng = $2::numeric, last_ping_at = now()
      WHERE id = $3::text`,
    [lat, lng, staffId],
  );
  if (!rowCount) return err(req, "Agent introuvable.", 404);
  return ok(req, { staffId }, "Position mise à jour.");
}

// ——————————————————————————————————————— Analytique période test (essai gratuit) ———
// L'app mobile POSTe un payload `lynkstor.trial.v1` (schéma stable, hors PII)
// déjà utilisé par le collecteur Drive. Ici les événements atterrissent dans
// la table unique `trial_analytics_events` ; le snapshot quotidien
// (`snapshot.daily`) est un événement dont `payload` porte les compteurs.
const ANALYTICS_EVENTS = new Set([
  "app.opened", "app.background", "onboarding.completed", "screen.viewed",
  "sale.completed", "product.created", "catalog.opened", "catalog.activated",
  "customer.created", "expense.created", "debt.collected", "ai.used",
  "snapshot.daily", "error.captured", "analytics.exported",
]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function handleAnalyticsIngest(req: Request): Promise<Response> {
  const body = await readJson(req);
  const installId = String(body.installId || "").trim();
  if (!installId || installId.length > 80) return err(req, "installId requis.");
  const rawEvents: any[] = Array.isArray(body.events) ? body.events : [];
  if (rawEvents.length > 200) return err(req, "Trop d'événements (max 200).");
  const sector = body.sector ? String(body.sector).slice(0, 40) : null;
  let accepted = 0;
  for (const ev of rawEvents) {
    if (!ev || typeof ev !== "object") continue;
    const name = String(ev.name || "");
    if (!ANALYTICS_EVENTS.has(name)) continue;
    const id = String(ev.id || "");
    if (!UUID_RE.test(id)) continue; // id = uuid (PK) côté Neon
    const createdAt = new Date(String(ev.createdAt || ""));
    const payload = ev.properties && typeof ev.properties === "object" ? JSON.stringify(ev.properties) : "{}";
    const res = await pool.query(
      `INSERT INTO trial_analytics_events (id, install_id, event_name, sector, payload, created_at)
       VALUES ($1::uuid,$2,$3,$4::text,$5::jsonb,$6::timestamptz)
       ON CONFLICT (id) DO NOTHING`,
      [id, installId, name, sector, payload,
       Number.isNaN(createdAt.getTime()) ? new Date().toISOString() : createdAt.toISOString()],
    );
    if (res.rowCount) accepted++;
  }
  return ok(req, { accepted });
}

async function handleAdminAnalyticsSummary(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const [totals, byNameRes, snapshotsRes] = await Promise.all([
    pool.query(
      `SELECT count(*)::int AS events, count(distinct install_id)::int AS installs
         FROM trial_analytics_events`,
    ),
    pool.query(`SELECT event_name, count(*)::int AS n FROM trial_analytics_events GROUP BY event_name`),
    pool.query(
      `SELECT distinct on (install_id) install_id, sector, payload, created_at
         FROM trial_analytics_events WHERE event_name = 'snapshot.daily'
        ORDER BY install_id, created_at DESC`,
    ),
  ]);
  const byEvent: Record<string, number> = {};
  for (const r of byNameRes.rows) byEvent[r.event_name] = r.n;
  const shops = snapshotsRes.rows.map((r: any) => {
    const p = r.payload || {};
    return {
      install_id: r.install_id,
      sector: p.sector || r.sector || null,
      sales_count: Number(p.salesCount || 0),
      sold_fcfa: Number(p.soldFcfa || 0),
      catalog_activated_count: Number(p.catalogActivatedCount || 0),
      open_days: Number(p.openDays || 0),
      captured_at: r.created_at,
    };
  });
  const bySector: Record<string, number> = {};
  let totalSoldFcfa = 0;
  let totalSales = 0;
  for (const s of shops) {
    const k = String(s.sector || "inconnu");
    bySector[k] = (bySector[k] || 0) + 1;
    totalSoldFcfa += s.sold_fcfa;
    totalSales += s.sales_count;
  }
  return success(req, {
    installs: totals.rows[0]?.installs ?? 0,
    events: totals.rows[0]?.events ?? 0,
    byEvent,
    bySector,
    totalSoldFcfa,
    totalSales,
    shops,
  });
}

async function handleAdminAnalyticsExport(req: Request): Promise<Response> {
  const guard = await requireAdmin(req);
  if (isAdminResponse(guard)) return guard;
  const { rows } = await pool.query(
    `SELECT id, install_id, event_name, sector, payload, created_at
       FROM trial_analytics_events ORDER BY created_at DESC LIMIT 5000`,
  );
  return success(req, rows);
}

// Activation express « terrain » : le commercial encaisse, l'admin active
// l'abonnement côté dashboard (le flux normal passe par /register + code).
async function handleAdminCommercialActivate(req: Request): Promise<Response> {
  const guard = await requireAdmin(req, true);
  if (isAdminResponse(guard)) return guard;
  const body = await readJson(req);
  const businessId = String(body.business_id || "").trim();
  const staffId = String(body.staff_id || "").trim();
  const planName = String(body.plan_name || "").trim() || "PRO (Mensuel)";
  const price = Number.isFinite(Number(body.price_fcfa)) ? Math.max(0, Number(body.price_fcfa)) : 15000;
  const months = Math.max(1, Math.min(36, parseInt(body.duration_months || "1", 10) || 1));
  const notes = String(body.notes || "Activation terrain commercial").slice(0, 300);
  if (!businessId || !staffId) return err(req, "business_id et staff_id requis.");
  const biz = await pool.query(`SELECT 1 FROM businesses WHERE id = $1`, [businessId]);
  if (!biz.rows.length) return err(req, "Commerce introuvable.", 404);
  const staff = await pool.query(`SELECT 1 FROM staff_accounts WHERE id = $1`, [staffId]);
  if (!staff.rows.length) return err(req, "Agent introuvable.", 404);
  const interval = `make_interval(months => ${months}::int)`; // entier borné, pas d'injection
  let sub = await pool.query(
    `UPDATE subscriptions SET status='active', plan_name=$2::text, price_fcfa=$3::numeric,
            expires_at = now() + ${interval}, updated_at = now()
      WHERE business_id = $1 RETURNING id, expires_at`,
    [businessId, planName, price],
  );
  if (!sub.rows.length) {
    sub = await pool.query(
      `INSERT INTO subscriptions (id, business_id, plan_name, status, price_fcfa, started_at, expires_at)
       VALUES ($1::uuid,$2,$3::text,'active',$4::numeric, now(), now() + ${interval})
       RETURNING id, expires_at`,
      [crypto.randomUUID(), businessId, planName, price],
    );
  }
  await pool.query(
    `INSERT INTO field_activities (id, staff_id, business_id, activity_type, amount_collected_fcfa, notes)
     VALUES ($1::uuid,$2::text,$3::text,'activation',$4::numeric,$5::text)`,
    [crypto.randomUUID(), staffId, businessId, price, notes],
  );
  const expiresAt = sub.rows[0]?.expires_at ? new Date(sub.rows[0].expires_at).toISOString().slice(0, 10) : "";
  return ok(req, { businessId, expiresAt }, `Abonnement ${planName} activé jusqu'au ${expiresAt}.`);
}

async function handleAdminSubscriptionUpdate(req: Request, id: string): Promise<Response> {
  const guard = await requireAdmin(req, true);
  if (isAdminResponse(guard)) return guard;
  const body = await readJson(req);
  const planName = String(body.plan_name || "").trim();
  const status = String(body.status || "").trim();
  const price = Number(body.price_fcfa);
  const expiresRaw = String(body.expires_at || "").trim();
  let expires: string | null = null;
  if (expiresRaw) {
    const d = new Date(expiresRaw);
    if (Number.isNaN(d.getTime())) return err(req, "expires_at invalide (YYYY-MM-DD).");
    expires = d.toISOString();
  }
  if (!planName) return err(req, "plan_name requis.");
  const allowedStatus = ["trial", "active", "expired", "suspended", "cancelled"];
  if (!allowedStatus.includes(status)) return err(req, `status invalide (${allowedStatus.join(" | ")}).`);
  if (!Number.isFinite(price) || price < 0) return err(req, "price_fcfa invalide.");
  const { rowCount } = await pool.query(
    `UPDATE subscriptions SET plan_name=$2::text, status=$3::text, price_fcfa=$4::numeric,
            expires_at=$5::timestamptz, updated_at=now()
      WHERE id = $1::text`,
    [id, planName, status, price, expires],
  );
  if (!rowCount) return err(req, "Abonnement introuvable.", 404);
  return ok(req, { id }, "Abonnement mis à jour.");
}

// ————————————————————————————————————————————————————————————— Router ———
async function route(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const m = req.method.toUpperCase();

  if (m === "GET" && (path === "/" || path === "/health"))
    return ok(req, { service: "Lynkstor Neon API Gateway", version: "1.0.0", timestamp: new Date().toISOString() });

  if (m === "GET" && (path === "/v1/config" || path === "/api/v1/config")) return handleConfig(req);
  if (m === "POST" && path === "/api/v1/register/validate") return handleRegisterValidate(req);
  if (m === "POST" && path === "/api/v1/register") return handleRegister(req);
  if (m === "GET" && path === "/api/v1/subscription/status") return handleSubscriptionStatus(req);
  if (m === "POST" && path === "/api/v1/invitations/create") return handleInvitationCreate(req);
  if (m === "POST" && path === "/api/v1/invitations/peek") return handleInvitationPeek(req);
  if (m === "POST" && path === "/api/v1/invitations/accept") return handleInvitationAccept(req);
  if (m === "POST" && path === "/api/v1/sync/push") return handleSyncPush(req);
  if (m === "GET" && path === "/api/v1/sync/pull") return handleSyncPull(req);
  if (m === "POST" && path === "/api/v1/auth/login") return handleLogin(req);
  if (m === "POST" && path === "/api/v1/license/issue") return handleLicenseIssue(req);
  if (m === "POST" && path === "/api/v1/analytics/ingest") return handleAnalyticsIngest(req);
  if (m === "POST" && (path === "/api/v1/webhooks/payment" || path === "/api/v1/payments/webhook"))
    return handlePaymentWebhook(req);

  // ——— Paiement abonnement Mobile Money (PawaPay, modèle push) ———
  if (m === "POST" && path === "/api/v1/payments/pawapay/webhook") return handlePawapayWebhook(req);
  if (m === "POST" && path === "/api/v1/payments/initiate") return handlePaymentInitiate(req);
  if (m === "GET" && path.startsWith("/api/v1/payments/")) {
    const pid = decodeURIComponent(path.slice("/api/v1/payments/".length));
    if (/^[0-9a-fA-F-]{36}$/.test(pid)) return handlePaymentStatus(req, pid);
  }

  // ——— Dashboard admin ———
  if (m === "GET" && path === "/api/v1/admin/stats") return handleAdminStats(req);
  if (m === "GET" && path === "/api/v1/admin/businesses") return handleAdminBusinesses(req, url);
  if (m === "GET" && path === "/api/v1/admin/codes") return handleAdminCodes(req, url);
  if (m === "POST" && path === "/api/v1/admin/codes/generate") return handleAdminCodesGenerate(req);
  if (m === "POST" && path === "/api/v1/admin/codes/preview") return handleAdminCodesPreview(req);
  if (m === "POST" && path === "/api/v1/admin/codes/revoke") return handleAdminCodesRevoke(req);
  if (m === "GET" && path === "/api/v1/admin/staff") return handleAdminStaff(req);
  if (m === "POST" && path === "/api/v1/admin/staff") return handleAdminStaffCreate(req);
  if (m === "POST" && path === "/api/v1/admin/staff/update") return handleAdminStaffUpdate(req);
  if (m === "DELETE" && path === "/api/v1/admin/staff") return handleAdminStaffDelete(req);
  if (m === "POST" && path === "/api/v1/admin/license/revoke") return handleAdminLicenseRevoke(req);
  if (m === "GET" && path === "/api/v1/admin/subscriptions") return handleAdminSubscriptions(req);
  if (m === "PUT" && path.startsWith("/api/v1/admin/subscriptions/")) {
    const subId = decodeURIComponent(path.slice("/api/v1/admin/subscriptions/".length));
    if (subId && !subId.includes("/")) return handleAdminSubscriptionUpdate(req, subId);
  }
  if (m === "GET" && path === "/api/v1/admin/analytics/summary") return handleAdminAnalyticsSummary(req);
  if (m === "GET" && path === "/api/v1/admin/analytics/export") return handleAdminAnalyticsExport(req);
  if (m === "POST" && path === "/api/v1/admin/commercial/activate") return handleAdminCommercialActivate(req);
  if (m === "GET" && path === "/api/v1/admin/field-activities") return handleAdminFieldActivities(req);
  if (m === "GET" && path === "/api/v1/admin/map-data") return handleAdminMapData(req);
  if (m === "GET" && path === "/api/v1/admin/users") return handleAdminUsers(req);
  if (m === "GET" && path === "/api/v1/admin/sync-logs") return handleAdminSyncLogs(req);
  if (m === "POST" && path === "/api/v1/commercial/ping") return handleCommercialPing(req);

  return err(req, "Not found", 404);
}

export default {
  async fetch(req: Request): Promise<Response> {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req) });
    try {
      return await route(req);
    } catch (e) {
      console.error("gateway error", e);
      return err(req, "Erreur interne du serveur.", 500);
    }
  },
};
