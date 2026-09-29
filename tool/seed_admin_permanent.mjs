// Crée/maj des comptes super_admin PERMANENTS dans Neon, en SQL direct
// (aucun admin vivant en prod -> on ne peut pas passer par /admin/staff).
// Hash pbkdf2 IDENTIQUE au gateway (verifyPassword/hashPassword) :
//   pbkdf2-sha256$210000$<saltHex>$<hashHex>
// Les mots de passe viennent de l'env (ADMIN_SPECS = JSON), JAMAIS affichés ;
// le script ne printed que le hash et la confirmation.
// Usage (PowerShell, dans la MEME commande que le pipe neon psql) :
//   $Env:ADMIN_SPECS='[{"id":"admin_permanent_miguel","username":"MIGUEL","fullName":"Miguel","password":"...","role":"super_admin"}]'
//   node tool/seed_admin_permanent.mjs | neon psql production --role-name neondb_owner
import crypto from "node:crypto";

const ITER = 210000, KEYLEN = 32;
function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.pbkdf2Sync(password, salt, ITER, KEYLEN, "sha256");
  return `pbkdf2-sha256$${ITER}$${salt.toString("hex")}$${hash.toString("hex")}`;
}
// Auto-vérif : reproduit la logique de verifyPassword du gateway.
function verify(password, stored) {
  const p = stored.split("$");
  if (p.length !== 4 || p[0] !== "pbkdf2-sha256") return false;
  const iter = parseInt(p[1], 10);
  const salt = Buffer.from(p[2], "hex");
  const want = Buffer.from(p[3], "hex");
  const got = crypto.pbkdf2Sync(password, salt, iter, want.length, "sha256");
  return got.length === want.length && crypto.timingSafeEqual(got, want);
}
function sqlStr(s) { return "'" + String(s).replace(/'/g, "''") + "'"; }

let specs;
try { specs = JSON.parse(process.env.ADMIN_SPECS || ""); }
catch { console.error("ADMIN_SPECS manquant ou JSON invalide."); process.exit(2); }
if (!Array.isArray(specs) || !specs.length) { console.error("ADMIN_SPECS doit etre un tableau non vide."); process.exit(2); }

const out = ["SET search_path TO lynkstor,public;", "BEGIN;"];
for (const s of specs) {
  if (!s.id || !s.username || !s.password) { console.error("spec incomplete: " + JSON.stringify({ id: s.id, username: s.username })); process.exit(2); }
  const role = s.role || "super_admin";
  if (!["super_admin", "supervisor", "commercial"].includes(role)) { console.error("role invalide: " + role); process.exit(2); }
  if (s.password.length < 12) { console.error("password trop court (<12) pour " + s.username); process.exit(2); }
  const hash = hashPassword(s.password);
  if (!verify(s.password, hash)) { console.error("auto-verif hash ECHOUE pour " + s.username); process.exit(1); }
  const fullName = s.fullName || s.username;
  out.push(
    `INSERT INTO staff_accounts (id, username, password_hash, full_name, role, status, token_version)
     VALUES (${sqlStr(s.id)}, ${sqlStr(s.username)}, ${sqlStr(hash)}, ${sqlStr(fullName)}, ${sqlStr(role)}, 'active', 1)
     ON CONFLICT (id) DO UPDATE SET
       username = EXCLUDED.username, password_hash = EXCLUDED.password_hash,
       full_name = EXCLUDED.full_name, role = EXCLUDED.role, status = 'active',
       token_version = staff_accounts.token_version + 1;`
  );
  console.error(`# ${s.username}: hash pbkdf2 auto-verifie OK (mp non affiche)`);
}
// Controle final sans exposer le hash complet.
out.push(
  `SELECT username, role, status, token_version, left(password_hash, 22) AS hash_prefix
     FROM staff_accounts
    WHERE id IN (${specs.map((s) => sqlStr(s.id)).join(", ")})
    ORDER BY username;`
);
out.push("COMMIT;");
console.log(out.join("\n"));
