// Generates tool/_seed_demo.sql: a plan, an available registration code,
// and a superadmin staff account (password "admin123", pbkdf2-sha256).
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const salt = crypto.randomBytes(16);
const hash = crypto.pbkdf2Sync("admin123", salt, 210000, 32, "sha256");
const ph = `pbkdf2-sha256$210000$${salt.toString("hex")}$${hash.toString("hex")}`;

const sql =
  `SET search_path TO lynkstor,public;\n` +
  `INSERT INTO plans (id,name,price_fcfa,billing_period,max_devices,features,is_active)\n` +
  `VALUES ('a0000000-0000-0000-0000-000000000001','STARTER',15000,'monthly',3,'{}'::jsonb,true)\n` +
  `ON CONFLICT (id) DO NOTHING;\n` +
  `INSERT INTO staff_accounts (id,full_name,email,username,phone,password_hash,role,status)\n` +
  `VALUES ('b0000000-0000-0000-0000-000000000001','Super Admin','admin@lynkstor.app','admin','','${ph}','super_admin','active')\n` +
  `ON CONFLICT (id) DO NOTHING;\n` +
  `INSERT INTO registration_codes (id,code,business_name,owner_phone,assigned_staff,plan_id,status)\n` +
  `VALUES (gen_random_uuid(),'LYNK-TEST-2026','Demo Shop','+2250700000000','b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','available')\n` +
  `ON CONFLICT DO NOTHING;\n` +
  `SELECT 'seeded' AS status;\n`;

const target = path.join(path.dirname(fileURLToPath(import.meta.url)), "_seed_demo.sql");
fs.writeFileSync(target, sql, "utf8");
console.log("wrote " + target);
console.log("staff password_hash length=" + ph.length + " (value not printed)");
