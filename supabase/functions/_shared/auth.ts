/** Compare timing-safe (best-effort en JS). */
export function safeEqual(a: string, b: string): boolean {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const enc = new TextEncoder();
  const ba = enc.encode(a);
  const bb = enc.encode(b);
  if (ba.length !== bb.length) return false;
  let out = 0;
  for (let i = 0; i < ba.length; i++) out |= ba[i] ^ bb[i];
  return out === 0;
}

export function extractBearer(req: Request): string | null {
  const h = req.headers.get("authorization") || "";
  if (h.toLowerCase().startsWith("bearer ")) return h.slice(7).trim();
  const apiKey = req.headers.get("x-api-key");
  return apiKey?.trim() || null;
}

export function getSecrets() {
  return {
    adminApiKey: Deno.env.get("ADMIN_API_KEY") || "",
    syncApiKey: Deno.env.get("SYNC_API_KEY") || "",
    adminUser: Deno.env.get("ADMIN_USER") || "admin",
    adminPassword: Deno.env.get("ADMIN_PASSWORD") || "",
    webhookSecret: Deno.env.get("WEBHOOK_SECRET") || "",
  };
}

async function signAdminPayload(payload: string): Promise<string> {
  const { adminApiKey } = getSecrets();
  if (!adminApiKey) {
    throw new Error("ADMIN_API_KEY is not configured");
  }
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(adminApiKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payload),
  );
  return bytesToBase64Url(new Uint8Array(signature));
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function base64UrlToString(value: string): string {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  return atob(padded);
}

export type AdminSession = {
  role: string;
  staff_id: string;
  full_name: string;
  exp: number;
};

export async function createAdminSessionToken(
  staff?: { id?: string; role?: string; full_name?: string },
): Promise<string> {
  const payload = bytesToBase64Url(
    new TextEncoder().encode(JSON.stringify({
      role: staff?.role || "super_admin",
      staff_id: staff?.id || "st-04",
      full_name: staff?.full_name || "Super Admin Lynkstor",
      exp: Date.now() + 12 * 60 * 60 * 1000,
    })),
  );
  return `${payload}.${await signAdminPayload(payload)}`;
}

export async function getAdminSession(
  token: string | null,
): Promise<AdminSession | null> {
  const { adminApiKey } = getSecrets();
  if (!token || !adminApiKey) return null;
  // NOTE (durcissement sécurité S5): le jeton ADMIN_API_KEY nu n'est PLUS
  // accepté comme session admin. Une session admin s'obtient uniquement via
  // /auth/login, qui délivre un jeton signé et expirant (createAdminSessionToken).
  // La clé nue ne sert plus qu'à signer/vérifier ces jetons.
  const parts = token.split(".");
  if (parts.length !== 2) return null;
  const expected = await signAdminPayload(parts[0]);
  if (!safeEqual(parts[1], expected)) return null;
  try {
    const payload = JSON.parse(base64UrlToString(parts[0])) as AdminSession;
    const validRoles = ["admin", "super_admin", "supervisor", "commercial"];
    if (
      !validRoles.includes(payload.role || "") ||
      !payload.staff_id ||
      Number(payload.exp) <= Date.now()
    ) {
      return null;
    }
    return payload;
  } catch (_) {
    return null;
  }
}

export async function isAdminToken(token: string | null): Promise<boolean> {
  return (await getAdminSession(token)) !== null;
}

export async function isSyncToken(token: string | null): Promise<boolean> {
  // Session admin signée → privilégiée (exports cross-tenant côté back-office).
  if (await isAdminToken(token)) return true;
  // NOTE (durcissement sécurité S2): on n'accepte PLUS la ADMIN_API_KEY en
  // repli. Une clé de sync partagée doit être explicite (SYNC_API_KEY) et
  // n'est destinée qu'à un serveur de confiance. Les appareils mobiles, eux,
  // utilisent un jeton par appareil (device_sync_tokens) scoping business_id.
  const { syncApiKey } = getSecrets();
  if (!token || !syncApiKey) return false;
  return safeEqual(token, syncApiKey);
}

export async function hashToken(token: string): Promise<string> {
  const dig = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(dig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

const passwordIterations = 210_000;

function base64UrlToBytes(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") +
    "=".repeat((4 - value.length % 4) % 4);
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

async function derivePassword(
  password: string,
  salt: Uint8Array,
  iterations: number,
): Promise<Uint8Array> {
  const material = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt: salt.buffer as ArrayBuffer,
      iterations,
    },
    material,
    256,
  );
  return new Uint8Array(bits);
}

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const derived = await derivePassword(password, salt, passwordIterations);
  return [
    "pbkdf2-sha256",
    passwordIterations,
    bytesToBase64Url(salt),
    bytesToBase64Url(derived),
  ].join("$");
}

export async function verifyPassword(
  password: string,
  stored: string,
): Promise<boolean> {
  const parts = stored.split("$");
  if (parts.length !== 4 || parts[0] !== "pbkdf2-sha256") {
    // NOTE (durcissement sécurité S7): aucun repli en comparaison « en clair ».
    // Tout mot de passe non haché au format PBKDF2 est refusé. Les comptes
    // legacy éventuels doivent être re-hachés (voir migration) et non tolerés.
    return false;
  }
  const iterations = Number(parts[1]);
  if (!Number.isInteger(iterations) || iterations < 120_000) return false;
  try {
    const salt = base64UrlToBytes(parts[2]);
    const expected = bytesToBase64Url(
      await derivePassword(password, salt, iterations),
    );
    return safeEqual(expected, parts[3]);
  } catch (_) {
    return false;
  }
}

/** Génère un code d'activation lisible (8 car. sans ambiguïté). */
export function generateActivationCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  let out = "";
  for (let i = 0; i < 8; i++) out += alphabet[bytes[i] % alphabet.length];
  return out;
}

export function generateSyncToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}
