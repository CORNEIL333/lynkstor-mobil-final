// Génère un jeton de licence Ed25519 signé par la VRAIE clé privée de prod,
// en reproduisant EXACTEMENT le schéma du gateway (fonctions/api/index.ts):
//   header = {alg,typ,kid};  claims = {businessId,plan,issuedAt,expiresAt,nonce,keyId,graceDays}
//   signingInput = b64url(JSON(header)) + "." + b64url(JSON(claims))
//   sig = Ed25519(utf8(signingInput));  token = signingInput + "." + b64url(sig)
// Sert de vecteur d'interop pour le test Dart Ed25519LicenseVerifier.
import crypto from "node:crypto";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

function loadEnv(file) {
  const out = {};
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/i);
    if (m) out[m[1]] = m[2].replace(/^"|"$/g, "");
  }
  return out;
}
const envPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", ".env.local");
const env = loadEnv(envPath);
const privPem = Buffer.from(env.LICENSE_PRIVATE_KEY_B64, "base64").toString("utf8");
const keyId = env.LICENSE_KEY_ID || "neon-2026-09";
const priv = crypto.createPrivateKey(privPem);

const b64url = (buf) => Buffer.from(buf).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const claims = {
  businessId: "biz-golden-0001",
  plan: "PRO",
  issuedAt: now,
  expiresAt: now + 3650 * 86400, // ~10 ans : stable pour les tests
  nonce: "golden0000000001",
  keyId,
  graceDays: 7,
};
const header = { alg: "Ed25519", typ: "JWT", kid: claims.keyId };
const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
const sig = crypto.sign(null, Buffer.from(signingInput, "utf8"), priv);
const token = `${signingInput}.${sig.toString("base64url")}`;

// Clé publique brute (dernières 32 octets de la SPKI DER).
const spki = crypto.createPublicKey(priv).export({ type: "spki", format: "der" });
const rawPub = spki.subarray(spki.length - 32).toString("base64url");

console.log("LICENSE_KEY_ID=" + keyId);
console.log("LICENSE_PUBLIC_RAW_B64URL=" + rawPub);
console.log("GOLDEN_TOKEN=" + token);

// Écrit aussi le jeton dans un fixture lu par le test Dart d'interop
// (évite toute corruption de recopie manuelle du token).
fs.mkdirSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "test", "fixtures"), { recursive: true });
fs.writeFileSync(
  path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "test", "fixtures", "golden_license.txt"),
  token,
  "utf8",
);
console.log("WROTE test/fixtures/golden_license.txt");
