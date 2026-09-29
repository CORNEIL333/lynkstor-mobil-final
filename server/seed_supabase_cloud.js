const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://wtbmwquovcizrtggkkzn.supabase.co';
// Préférer SERVICE_ROLE pour contourner le RLS (sinon les inserts échouent).
// Legacy Supabase (déprécié) : aucune clé n'est embarquée dans le dépôt.
const SUPABASE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY || '';
if (!SUPABASE_KEY) {
  console.error('SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY manquant (legacy déprécié).');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

async function seedCloud() {
  console.log('🌱 Injection des données initiales dans Supabase Cloud...');

  // 1. Commerces avec GPS
  const businesses = [
    { id: 'biz-01', name: 'Alimentation Générale la Grâce', sector: 'epicerie', phone: '+2250708091011', owner_name: 'Kouamé Jean', status: 'active', latitude: 5.3484, longitude: -4.0305 },
    { id: 'biz-02', name: 'Pharmacie & Parfumerie du Centre', sector: 'pharmacie', phone: '+2250504030201', owner_name: 'Dr. Aminata Diallo', status: 'active', latitude: 5.3261, longitude: -4.0211 },
    { id: 'biz-03', name: 'Boutique Quincaillerie Moderne', sector: 'quincaillerie', phone: '+221776543210', owner_name: 'Mamadou Ndiaye', status: 'active', latitude: 5.3598, longitude: -3.9891 },
    { id: 'biz-04', name: 'Dépôt de Boissons le Jardin', sector: 'grossiste', phone: '+22890112233', owner_name: 'Kofi Messan', status: 'active', latitude: 5.3712, longitude: -4.0150 }
  ];

  const { error: errBiz } = await supabase.from('businesses').upsert(businesses);
  if (errBiz) console.error('Error inserting businesses:', errBiz.message);
  else console.log('✅ Commerces insérés dans le Cloud Supabase !');

  // 2. Abonnements
  const subscriptions = [
    { id: 'sub-01', business_id: 'biz-01', plan_name: 'PRO (Mensuel)', status: 'active', price_fcfa: 15000, expires_at: '2026-12-31' },
    { id: 'sub-02', business_id: 'biz-02', plan_name: 'ENTERPRISE (Annuel)', status: 'active', price_fcfa: 150000, expires_at: '2027-06-30' },
    { id: 'sub-03', business_id: 'biz-03', plan_name: 'STARTER', status: 'active', price_fcfa: 5000, expires_at: '2026-09-15' },
    { id: 'sub-04', business_id: 'biz-04', plan_name: 'GRATUIT (Essai)', status: 'expired', price_fcfa: 0, expires_at: '2026-07-01' }
  ];

  const { error: errSub } = await supabase.from('subscriptions').upsert(subscriptions);
  if (errSub) console.error('Error inserting subscriptions:', errSub.message);
  else console.log('✅ Abonnements insérés !');

  // 3. Comptes Staff
  const staff = [
    { id: 'st-01', full_name: 'Amadou Koné', email: 'kone@lynkstor.com', phone: '+2250701020304', role: 'commercial', status: 'active', current_lat: 5.3510, current_lng: -4.0280 },
    { id: 'st-02', full_name: 'Sandrine Bamba', email: 'bamba@lynkstor.com', phone: '+2250505060708', role: 'commercial', status: 'active', current_lat: 5.3300, current_lng: -4.0180 },
    { id: 'st-03', full_name: 'Marc Kouassi', email: 'kouassi@lynkstor.com', phone: '+2250102030405', role: 'supervisor', status: 'active' },
    { id: 'st-04', full_name: 'Super Admin Lynkstor', email: 'admin@lynkstor.com', phone: '+2250000000000', role: 'super_admin', status: 'active' }
  ];

  const { error: errStaff } = await supabase.from('staff_accounts').upsert(staff);
  if (errStaff) console.error('Error inserting staff:', errStaff.message);
  else console.log('✅ Comptes Staff insérés !');

  console.log('🎉 Seed Supabase Cloud Terminé avec Succès !');
}

seedCloud();
