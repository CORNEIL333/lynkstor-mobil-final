import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const separator = trimmed.indexOf("=");
    if (separator < 1) continue;
    const key = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim();
    if (!process.env[key]) process.env[key] = value;
  }
}

loadEnvFile(path.join(root, "deploy", "PROJECT.env"));
loadEnvFile(path.join(root, "deploy", "secrets.local.env"));

const supabaseUrl =
  process.env.SUPABASE_URL ||
  "https://wtbmwquovcizrtggkkzn.supabase.co";
const apiBase = `${supabaseUrl}/functions/v1/lynkstor-api`;
const anonKey = process.env.SUPABASE_ANON_KEY;
const adminUser = process.env.ADMIN_USER;
const adminPassword = process.env.ADMIN_PASSWORD;

for (const [name, value] of Object.entries({
  SUPABASE_ANON_KEY: anonKey,
  ADMIN_USER: adminUser,
  ADMIN_PASSWORD: adminPassword,
})) {
  if (!value) throw new Error(`${name} manquant`);
}

async function request(route, { method = "GET", token = anonKey, body } = {}) {
  const response = await fetch(`${apiBase}${route}`, {
    method,
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  return { response, payload };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const suffix = crypto.randomUUID();
const businessId = `verify-biz-${suffix}`;
const userId = `verify-user-${suffix}`;
let activationCode = null;
let staffId = null;

async function cleanup() {
  const codeFilter = activationCode
    ? `DELETE FROM registration_codes WHERE code = '${activationCode}';`
    : "";
  const sql = `
    BEGIN;
    ${codeFilter}
    DELETE FROM payment_webhook_events WHERE business_id = '${businessId}';
    DELETE FROM device_sync_cursors WHERE business_id = '${businessId}';
    DELETE FROM sync_entities WHERE business_id = '${businessId}';
    DELETE FROM sync_events WHERE business_id = '${businessId}';
    DELETE FROM sales_summary WHERE business_id = '${businessId}';
    DELETE FROM field_activities WHERE business_id = '${businessId}';
    DELETE FROM device_sync_tokens WHERE business_id = '${businessId}';
    DELETE FROM subscriptions WHERE business_id = '${businessId}';
    DELETE FROM users WHERE business_id = '${businessId}';
    DELETE FROM businesses WHERE id = '${businessId}';
    ${staffId ? `DELETE FROM staff_accounts WHERE id = '${staffId}';` : ""}
    COMMIT;
  `;
  const result = spawnSync(
    "supabase",
    ["db", "query", "--linked", sql],
    { cwd: root, encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(
      `Nettoyage Supabase impossible: ${result.stderr || result.stdout}`,
    );
  }
}

try {
  const health = await request("/health");
  assert(health.response.ok && health.payload.status === "ok", "health");
  console.log("OK health");

  const login = await request("/api/v1/auth/login", {
    method: "POST",
    body: { username: adminUser, password: adminPassword },
  });
  assert(login.response.ok && login.payload.token, "admin login");
  const adminToken = login.payload.token;
  console.log("OK admin login");

  const staffUsername = `verify_${suffix.replaceAll("-", "").slice(0, 20)}`;
  const staffPassword = `Verify-${suffix}-A1!`;
  const staffCreation = await request("/api/v1/admin/staff", {
    method: "POST",
    token: adminToken,
    body: {
      full_name: "Agent vérification automatique",
      username: staffUsername,
      password: staffPassword,
      email: `${staffUsername}@example.invalid`,
      phone: `verify-${suffix}`,
      role: "commercial",
    },
  });
  staffId = staffCreation.payload.id || null;
  assert(
    staffCreation.response.status === 201 && staffId,
    `staff creation (${staffCreation.response.status}): ${
      JSON.stringify(staffCreation.payload)
    }`,
  );
  console.log("OK staff creation");

  const staffLogin = await request("/api/v1/auth/login", {
    method: "POST",
    body: { username: staffUsername, password: staffPassword },
  });
  assert(
    staffLogin.response.ok &&
      staffLogin.payload.role === "commercial" &&
      staffLogin.payload.staff_id === staffId,
    "staff login and role",
  );
  console.log("OK staff login and role");

  const forbiddenStaffList = await request("/api/v1/admin/staff", {
    token: staffLogin.payload.token,
  });
  assert(forbiddenStaffList.response.status === 403, "staff role restriction");
  console.log("OK staff role restriction");

  const generated = await request("/api/v1/admin/activation-codes/generate", {
    method: "POST",
    token: adminToken,
    body: {
      staff_id: staffId,
      plan_name: "STARTER",
      duration_months: 1,
      count: 1,
    },
  });
  activationCode = generated.payload.codes?.[0] || null;
  assert(
    generated.response.status === 201 && activationCode,
    `code generation (${generated.response.status}): ${
      JSON.stringify(generated.payload)
    }`,
  );
  console.log("OK activation code generation");

  const validation = await request("/api/v1/register/validate", {
    method: "POST",
    body: { activationCode },
  });
  assert(
    validation.response.ok && validation.payload.data?.valid === true,
    "code validation",
  );
  console.log("OK activation code validation");

  const registrationBody = {
    activationCode,
    business: {
      id: businessId,
      name: "Commerce vérification automatique",
      ownerName: "Test Lynkstor",
      phone: `verify-${suffix}`,
      sector: "boutique",
      city: "Test",
      neighborhood: "Test",
    },
    user: {
      id: userId,
      fullName: "Test Lynkstor",
      phone: `verify-${suffix}`,
    },
  };
  const registration = await request("/api/v1/register", {
    method: "POST",
    body: registrationBody,
  });
  assert(
    registration.response.status === 201 &&
      registration.payload.data?.businessId === businessId &&
      registration.payload.data?.syncToken,
    "business registration",
  );
  const syncToken = registration.payload.data.syncToken;
  console.log("OK business registration");

  const recovery = await request("/api/v1/register", {
    method: "POST",
    body: registrationBody,
  });
  assert(
    recovery.response.status === 201 &&
      recovery.payload.data?.businessId === businessId &&
      recovery.payload.data?.syncToken,
    "idempotent registration recovery",
  );
  console.log("OK idempotent registration recovery");

  const subscription = await request("/api/v1/subscription/status", {
    token: syncToken,
  });
  assert(
    subscription.response.ok &&
      subscription.payload.data?.businessId === businessId &&
      subscription.payload.data?.licenseActive === true,
    "subscription status",
  );
  console.log("OK subscription status");

  const syncBody = {
    id: `verify-sync-${suffix}`,
    businessId,
    entityType: "business",
    entityId: businessId,
    operation: "update",
    payload: { verified: true, version: 2 },
    entityVersion: 2,
  };
  const sync = await request("/api/v1/sync/push", {
    method: "POST",
    token: syncToken,
    body: syncBody,
  });
  assert(
    sync.response.status === 201 &&
      Number.isInteger(Number(sync.payload.serverSeq)),
    "sync push",
  );
  console.log("OK sync push");

  const duplicateSync = await request("/api/v1/sync/push", {
    method: "POST",
    token: syncToken,
    body: syncBody,
  });
  assert(
    duplicateSync.response.status === 200 &&
      duplicateSync.payload.duplicate === true &&
      Number(duplicateSync.payload.serverSeq) ===
        Number(sync.payload.serverSeq),
    "idempotent sync push",
  );
  console.log("OK idempotent sync push");

  const pull = await request(
    `/api/v1/sync/pull?businessId=${businessId}&cursor=0&limit=100`,
    { token: syncToken },
  );
  assert(
    pull.response.ok &&
      pull.payload.items?.some((item) => item.id === syncBody.id) &&
      Number(pull.payload.nextCursor) >= Number(sync.payload.serverSeq),
    "cursor sync pull",
  );
  console.log("OK cursor sync pull");

  const emptyPull = await request(
    `/api/v1/sync/pull?businessId=${businessId}&cursor=${
      encodeURIComponent(pull.payload.nextCursor)
    }&limit=100`,
    { token: syncToken },
  );
  assert(
    emptyPull.response.ok &&
      emptyPull.payload.items?.length === 0 &&
      Number(emptyPull.payload.nextCursor) ===
        Number(pull.payload.nextCursor),
    "cursor resume",
  );
  console.log("OK cursor resume");

  const stats = await request("/api/v1/admin/stats", {
    token: adminToken,
  });
  assert(
    stats.response.ok &&
      Number.isInteger(stats.payload.data?.totalCodes) &&
      Number.isInteger(stats.payload.data?.availableCodes),
    "admin stats",
  );
  console.log("OK admin stats");

  const invalidWebhook = await request("/api/v1/payments/webhook", {
    method: "POST",
    body: {
      business_id: businessId,
      transaction_id: `verify-tx-${suffix}`,
      status: "SUCCESS",
    },
  });
  assert(invalidWebhook.response.status === 401, "webhook signature rejection");
  console.log("OK webhook signature rejection");
} finally {
  await cleanup();
  console.log("OK cleanup");
}
