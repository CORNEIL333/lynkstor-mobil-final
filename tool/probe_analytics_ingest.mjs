// Probe ponctuel : reproduit EXACTEMENT la requête d'envoi de
// lib/shared/services/analytics_service.dart (_postJson : Content-Type
// text/plain;charset=utf-8, schema lynkstor.trial.v1, champs `events`
// {id,name,properties,createdAt} + `evenements` redondants + snapshot
// camelCase) contre le gateway Neon de production.
// Usage: node tool/probe_analytics_ingest.mjs   (puis --purge pour nettoyer)
const BASE = (process.env.NEON_API_BASE || "https://br-curly-mud-b11jrchz-api.compute.c-5.eu-central-1.aws.neon.tech").replace(/\/+$/, "");
const INSTALL = "e2e-probe-analytics"; // matche le motif de purge existant install_id LIKE 'e2e-%'

if (process.argv.includes("--purge")) {
  // Le probe ne peut pas parler SQL directement : on laisse le purge Neon
  // (tool/purge_neon_demo.sql, cible install_id LIKE 'e2e-%' ou liste fixée là)
  // s'en charger. Purge ciblé via le gateway = inexistant -> sortie informative.
  console.log("Purge du probe via tool/purge_neon_demo.sql (ajoute la cible install_id = '" + INSTALL + "' si besoin).");
  process.exit(0);
}

const uuid = () => crypto.randomUUID();
const payload = JSON.stringify({
  schema: "lynkstor.trial.v1",
  folderId: "",
  app: "Lynkstor",
  appVersion: "1.0.0+1",
  sentAt: new Date().toISOString(),
  installId: INSTALL,
  businessId: null,
  sector: "general",
  boutique: { install_id: INSTALL, secteur: "general", nb_evenements: 2 },
  device: { os: "android", osVersion: "probe" },
  snapshot: { salesCount: 3, soldFcfa: 4500, productsCount: 2, catalogActivatedCount: 1, customersCount: 1, expensesCount: 0, eventCount: 2, pendingCount: 0, openDays: 2, sector: "general", lastOpenAt: new Date().toISOString() },
  events: [
    { id: uuid(), name: "app.opened", properties: {}, createdAt: new Date().toISOString() },
    { id: uuid(), name: "snapshot.daily", properties: { salesCount: 3, soldFcfa: 4500, openDays: 2, sector: "general" }, createdAt: new Date().toISOString() },
    { id: uuid(), name: "pii.attempt", properties: {}, createdAt: new Date().toISOString() },
  ],
  evenements: [],
});

const res = await fetch(BASE + "/api/v1/analytics/ingest", {
  method: "POST",
  headers: { "Content-Type": "text/plain;charset=utf-8" },
  body: payload,
});
const json = await res.json().catch(() => null);
console.log("HTTP", res.status, JSON.stringify(json));
console.log(res.status === 200 && json?.data?.accepted === 2
  ? "PASS : la requete facon app est acceptee (2/3, nom inconnu jete) -> installer le purge apres."
  : "FAIL : contract mismatch ?");
process.exit(res.status === 200 && json?.data?.accepted === 2 ? 0 : 1);
