/**
 * Seed Supabase avec service_role + vérif tables.
 * Usage:
 *   set SUPABASE_SERVICE_ROLE_KEY=eyJ...
 *   node apply_remote.js
 */
const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');

function loadEnv(p) {
  if (!fs.existsSync(p)) return;
  for (const line of fs.readFileSync(p, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const i = t.indexOf('=');
    if (i < 0) continue;
    const k = t.slice(0, i).trim();
    const v = t.slice(i + 1).trim();
    if (!process.env[k]) process.env[k] = v;
  }
}

loadEnv(path.join(__dirname, '../deploy/secrets.local.env'));
loadEnv(path.join(__dirname, '../deploy/PROJECT.env'));

const URL = process.env.SUPABASE_URL || 'https://wtbmwquovcizrtggkkzn.supabase.co';
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!KEY || KEY.includes('COLLEZ')) {
  console.error(`
❌ SUPABASE_SERVICE_ROLE_KEY manquante.

Avec la clé anon seule je NE PEUX PAS :
  • créer registration_codes
  • seed (RLS bloque)
  • déployer les Edge Functions

1) Dashboard → Settings → API → copier **service_role** (secret)
2) Créer deploy/secrets.local.env :
   SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...
3) SQL Editor → coller supabase/APPLY_ALL.sql → Run
4) node server/apply_remote.js
5) npx supabase functions deploy lynkstor-api --project-ref wtbmwquovcizrtggkkzn --no-verify-jwt
`);
  process.exit(1);
}

const sb = createClient(URL, KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

async function upsert(table, rows) {
  const { error } = await sb.from(table).upsert(rows, { onConflict: 'id' });
  if (error) {
    console.error(`❌ ${table}:`, error.message);
    return false;
  }
  console.log(`✅ ${table}: ${rows.length}`);
  return true;
}

(async () => {
  console.log('🌐', URL);

  const { error: rcErr } = await sb.from('registration_codes').select('id').limit(1);
  if (rcErr) {
    console.error('❌ registration_codes absente. Exécutez d’abord supabase/APPLY_ALL.sql dans le SQL Editor.');
    console.error(rcErr.message);
    process.exit(1);
  }

  await upsert('businesses', [
    { id: 'biz-01', name: 'Alimentation Générale la Grâce', sector: 'epicerie', phone: '+2250708091011', owner_name: 'Kouamé Jean', status: 'active', latitude: 5.3484, longitude: -4.0305, registration_source: 'seed' },
    { id: 'biz-02', name: 'Pharmacie & Parfumerie du Centre', sector: 'pharmacie', phone: '+2250504030201', owner_name: 'Dr. Aminata Diallo', status: 'active', latitude: 5.3261, longitude: -4.0211, registration_source: 'seed' },
    { id: 'biz-03', name: 'Boutique Quincaillerie Moderne', sector: 'quincaillerie', phone: '+221776543210', owner_name: 'Mamadou Ndiaye', status: 'active', latitude: 5.3598, longitude: -3.9891, registration_source: 'seed' },
    { id: 'biz-04', name: 'Dépôt de Boissons le Jardin', sector: 'grossiste', phone: '+22890112233', owner_name: 'Kofi Messan', status: 'active', latitude: 5.3712, longitude: -4.0150, registration_source: 'seed' },
  ]);

  await upsert('users', [
    { id: 'u-01', business_id: 'biz-01', full_name: 'Kouamé Jean', phone: '+2250708091011', role: 'owner', status: 'active', is_owner: true },
    { id: 'u-02', business_id: 'biz-01', full_name: 'Yao Marc', phone: '+2250102030405', role: 'seller', status: 'active', is_owner: false },
    { id: 'u-03', business_id: 'biz-02', full_name: 'Dr. Aminata Diallo', phone: '+2250504030201', role: 'owner', status: 'active', is_owner: true },
    { id: 'u-04', business_id: 'biz-03', full_name: 'Mamadou Ndiaye', phone: '+221776543210', role: 'owner', status: 'active', is_owner: true },
    { id: 'u-05', business_id: 'biz-04', full_name: 'Kofi Messan', phone: '+22890112233', role: 'owner', status: 'suspended', is_owner: true },
  ]);

  await upsert('subscriptions', [
    { id: 'sub-01', business_id: 'biz-01', plan_name: 'PRO (Mensuel)', status: 'active', price_fcfa: 15000, expires_at: '2026-12-31' },
    { id: 'sub-02', business_id: 'biz-02', plan_name: 'ENTERPRISE (Annuel)', status: 'active', price_fcfa: 150000, expires_at: '2027-06-30' },
    { id: 'sub-03', business_id: 'biz-03', plan_name: 'STARTER', status: 'active', price_fcfa: 5000, expires_at: '2026-09-15' },
    { id: 'sub-04', business_id: 'biz-04', plan_name: 'GRATUIT (Essai)', status: 'expired', price_fcfa: 0, expires_at: '2026-07-01' },
  ]);

  await upsert('staff_accounts', [
    { id: 'st-01', full_name: 'Amadou Koné', email: 'kone@lynkstor.com', phone: '+2250701020304', role: 'commercial', status: 'active', current_lat: 5.351, current_lng: -4.028 },
    { id: 'st-02', full_name: 'Sandrine Bamba', email: 'bamba@lynkstor.com', phone: '+2250505060708', role: 'commercial', status: 'active', current_lat: 5.33, current_lng: -4.018 },
    { id: 'st-03', full_name: 'Marc Kouassi', email: 'kouassi@lynkstor.com', phone: '+2250102030405', role: 'supervisor', status: 'active' },
    { id: 'st-04', full_name: 'Super Admin Lynkstor', email: 'admin@lynkstor.com', phone: '+2250000000000', role: 'super_admin', status: 'active' },
  ]);

  await upsert('sales_summary', [
    { id: 's-1', business_id: 'biz-01', amount_fcfa: 125000, payment_method: 'Espèces' },
    { id: 's-2', business_id: 'biz-01', amount_fcfa: 450000, payment_method: 'Orange Money' },
    { id: 's-3', business_id: 'biz-02', amount_fcfa: 890000, payment_method: 'MTN MoMo' },
    { id: 's-4', business_id: 'biz-03', amount_fcfa: 340000, payment_method: 'Espèces' },
    { id: 's-5', business_id: 'biz-04', amount_fcfa: 620000, payment_method: 'Wave' },
  ]);

  const exp = new Date();
  exp.setDate(exp.getDate() + 30);
  await upsert('registration_codes', [
    { id: 'rc-demo-1', code: 'DEMO0001', staff_id: 'st-01', plan_name: 'STARTER', price_fcfa: 5000, duration_months: 1, status: 'unused', notes: 'Code test', expires_at: exp.toISOString() },
    { id: 'rc-demo-2', code: 'DEMO0002', staff_id: 'st-01', plan_name: 'PRO (Mensuel)', price_fcfa: 15000, duration_months: 1, status: 'unused', notes: 'Code test', expires_at: exp.toISOString() },
    { id: 'rc-demo-3', code: 'AGENT001', staff_id: 'st-02', plan_name: 'STARTER', price_fcfa: 5000, duration_months: 1, status: 'unused', notes: 'Code test', expires_at: exp.toISOString() },
  ]);

  const { count } = await sb.from('businesses').select('*', { count: 'exact', head: true });
  console.log(`\n🎉 Seed OK — commerces: ${count}`);
  console.log('Codes app : DEMO0001 | DEMO0002 | AGENT001');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
