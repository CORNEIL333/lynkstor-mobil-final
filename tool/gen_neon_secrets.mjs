// Generates Neon Function secrets into the gitignored .env.local (idempotent).
// NEVER prints secret values. Prints only public key material + key id.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const envPath = path.join(root, ".env.local");

const KEY_ID = "neon-2026-09";

// Ed25519 keypair. Private PEM is base64-packed to a single line so it survives
// the dotenv parser used by `neon deploy --env`.
const { privateKey, publicKey } = crypto.generateKeyPairSync("ed25519");
const privPem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const pubPem = publicKey.export({ type: "spki", format: "pem" }).toString();
const privB64 = Buffer.from(privPem, "utf8").toString("base64");
// Raw 32-byte public key = trailing 32 bytes of the SPKI DER.
const spkiDer = publicKey.export({ type: "spki", format: "der" });
const pubRawB64Url = spkiDer.subarray(spkiDer.length - 32).toString("base64url");

const secret = (n) => crypto.randomBytes(n).toString("hex");

const want = {
  LICENSE_KEY_ID: KEY_ID,
  LICENSE_PRIVATE_KEY_B64: privB64,
  ADMIN_SESSION_SECRET: secret(32),
  PAYMENT_WEBHOOK_SECRET: secret(32),
  CORS_ALLOWED_ORIGIN: "*",
  MIN_SUPPORTED_VERSION: "1.0.0",
  LATEST_VERSION: "1.2.0",
  MAINTENANCE: "false",
  KILL_MODULES: "",
  MAX_OFFLINE_DAYS: "30",
  REQUIRE_AGENT_ACTIVATION_CODE: "true",
  TRIAL_DAYS: "14",
  TRIAL_PLAN_NAME: "STARTER",
  TRIAL_PRICE_FCFA: "15000",
};

let existing = "";
if (fs.existsSync(envPath)) existing = fs.readFileSync(envPath, "utf8");
const haveKeys = new Set(
  existing
    .split(/\r?\n/)
    .filter((l) => /^[A-Z0-9_]+=/.test(l))
    .map((l) => l.split("=")[0]),
);

const lines = [];
for (const [k, v] of Object.entries(want)) {
  if (haveKeys.has(k)) continue; // do not overwrite existing values
  lines.push(`${k}=${v}`);
}
if (lines.length) {
  const block = `\n# --- Lynkstor Neon Function secrets (generated ${new Date().toISOString()}) ---\n${lines.join("\n")}\n`;
  fs.writeFileSync(envPath, existing.replace(/\s*$/, "") + block, "utf8");
}

// Public material only — safe to display.
console.log("LICENSE_KEY_ID=" + KEY_ID);
console.log("LICENSE_PUBLIC_PEM<<EOF");
console.log(pubPem.trim());
console.log("EOF");
console.log("LICENSE_PUBLIC_RAW_B64URL=" + pubRawB64Url);
console.log("SECRETS_APPENDED=" + lines.length + " (to .env.local, gitignored)");
