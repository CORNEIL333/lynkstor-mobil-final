/**
 * Prépare le bundle statique Cloudflare (dashboard admin) à partir de server/public.
 *
 * Usage:
 *   node deploy/cloudflare/prepare.mjs
 *   NEON_API_BASE=https://<branch>-api.compute.<region>.aws.neon.tech node deploy/cloudflare/prepare.mjs
 * Sans env, l'apiBase est reprise de server/public/config.js (gateway Neon courant).
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "../..");
const src = path.join(root, "server", "public");
const dist = path.join(__dirname, "dist");

function copyDir(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const s = path.join(from, entry.name);
    const d = path.join(to, entry.name);
    if (entry.isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
}

if (fs.existsSync(dist)) fs.rmSync(dist, { recursive: true, force: true });
copyDir(src, dist);
fs.copyFileSync(path.join(__dirname, "_headers"), path.join(dist, "_headers"));

// Reprendre l'apiBase de la config source (gateway Neon courant) si fournie.
let sourceApiBase = "";
const srcConfigPath = path.join(src, "config.js");
if (fs.existsSync(srcConfigPath)) {
  const raw = fs.readFileSync(srcConfigPath, "utf8");
  const mBase = raw.match(/apiBase:\s*["']([^"']+)["']/);
  if (mBase) sourceApiBase = mBase[1];
}

const apiBase = (process.env.NEON_API_BASE || sourceApiBase || "").replace(/\/+$/, "");
if (!apiBase) {
  throw new Error("apiBase vide : sets NEON_API_BASE ou renseigne server/public/config.js");
}

const config = `/**
 * Généré par deploy/cloudflare/prepare.mjs
 * ${new Date().toISOString()}
 */
window.LYNKSTOR_CONFIG = {
  mode: "neon",
  apiBase: ${JSON.stringify(apiBase)},
};
window.LYNKSTOR_API_BASE = window.LYNKSTOR_CONFIG.apiBase;
`;

fs.writeFileSync(path.join(dist, "config.js"), config, "utf8");

console.log("✓ Bundle Cloudflare prêt :", dist);
console.log("✓ apiBase =", apiBase);
