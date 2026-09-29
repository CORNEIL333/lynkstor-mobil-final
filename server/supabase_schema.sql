-- ======================================================
-- SCRIPT SQL SUPABASE — LYNKSTOR (copie de la migration)
-- Préférer : supabase/migrations/20260727000000_init.sql
-- Voir docs/SUPABASE_CLOUDFLARE_DEPLOYMENT.md
-- ======================================================

-- 1. Commerces
CREATE TABLE IF NOT EXISTS businesses (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  sector TEXT DEFAULT 'general',
  phone TEXT,
  owner_name TEXT,
  status TEXT DEFAULT 'active',
  latitude NUMERIC DEFAULT 5.3484,
  longitude NUMERIC DEFAULT -4.0305,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Utilisateurs clients
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  business_id TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL,
  phone TEXT,
  role TEXT DEFAULT 'seller',
  status TEXT DEFAULT 'active',
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Abonnements
CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  plan_name TEXT DEFAULT 'PRO',
  status TEXT DEFAULT 'active',
  price_fcfa NUMERIC DEFAULT 15000,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Staff terrain (Admin, Superviseur, Commercial)
CREATE TABLE IF NOT EXISTS staff_accounts (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE,
  password_hash TEXT,
  full_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  role TEXT CHECK(role IN ('super_admin', 'supervisor', 'commercial')) DEFAULT 'commercial',
  status TEXT DEFAULT 'active',
  current_lat NUMERIC,
  current_lng NUMERIC,
  last_ping_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Clés d'activation uniques par commercial
CREATE TABLE IF NOT EXISTS activation_codes (
  code TEXT PRIMARY KEY,
  staff_id TEXT NOT NULL REFERENCES staff_accounts(id) ON DELETE CASCADE,
  created_by_staff_id TEXT REFERENCES staff_accounts(id) ON DELETE SET NULL,
  plan_name TEXT DEFAULT 'PRO (Mensuel)',
  duration_months INTEGER DEFAULT 1,
  status TEXT CHECK(status IN ('available', 'used', 'revoked', 'expired')) DEFAULT 'available',
  business_id TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  activated_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Activités terrain
CREATE TABLE IF NOT EXISTS field_activities (
  id TEXT PRIMARY KEY,
  staff_id TEXT NOT NULL REFERENCES staff_accounts(id) ON DELETE CASCADE,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  activity_type TEXT CHECK(activity_type IN ('activation', 'collection', 'visit')) DEFAULT 'activation',
  amount_collected_fcfa NUMERIC DEFAULT 0,
  notes TEXT,
  latitude NUMERIC,
  longitude NUMERIC,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Sync events (journal)
CREATE TABLE IF NOT EXISTS sync_events (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  entity_type TEXT,
  entity_id TEXT,
  operation TEXT,
  payload_json JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_events_business_created
  ON sync_events (business_id, created_at);

-- 7. Synthèse ventes (KPI)
CREATE TABLE IF NOT EXISTS sales_summary (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  amount_fcfa NUMERIC NOT NULL,
  payment_method TEXT DEFAULT 'Espèces',
  sold_at TIMESTAMPTZ DEFAULT NOW()
);

-- ======================================================
-- RLS : sécurisé par défaut (aucun accès anon)
-- Accès applicatif via service_role côté serveur uniquement.
-- ======================================================
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_summary ENABLE ROW LEVEL SECURITY;

-- Pas de policy pour "anon" / "authenticated" → refus par défaut.
-- Le rôle service_role bypass RLS (à n’utiliser que serveur à serveur).

-- Seed démo (optionnel — environnement de test uniquement)
INSERT INTO businesses (id, name, sector, phone, owner_name, status, latitude, longitude) VALUES
  ('biz-01', 'Alimentation Générale la Grâce', 'epicerie', '+2250708091011', 'Kouamé Jean', 'active', 5.3484, -4.0305),
  ('biz-02', 'Pharmacie & Parfumerie du Centre', 'pharmacie', '+2250504030201', 'Dr. Aminata Diallo', 'active', 5.3261, -4.0211),
  ('biz-03', 'Boutique Quincaillerie Moderne', 'quincaillerie', '+221776543210', 'Mamadou Ndiaye', 'active', 5.3598, -3.9891),
  ('biz-04', 'Dépôt de Boissons le Jardin', 'grossiste', '+22890112233', 'Kofi Messan', 'active', 5.3712, -4.0150)
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (id, business_id, full_name, phone, role, status) VALUES
  ('u-01', 'biz-01', 'Kouamé Jean', '+2250708091011', 'owner', 'active'),
  ('u-02', 'biz-01', 'Yao Marc', '+2250102030405', 'seller', 'active'),
  ('u-03', 'biz-02', 'Dr. Aminata Diallo', '+2250504030201', 'owner', 'active'),
  ('u-04', 'biz-03', 'Mamadou Ndiaye', '+221776543210', 'owner', 'active'),
  ('u-05', 'biz-04', 'Kofi Messan', '+22890112233', 'owner', 'suspended')
ON CONFLICT (id) DO NOTHING;

INSERT INTO subscriptions (id, business_id, plan_name, status, price_fcfa, expires_at) VALUES
  ('sub-01', 'biz-01', 'PRO (Mensuel)', 'active', 15000, '2026-12-31'),
  ('sub-02', 'biz-02', 'ENTERPRISE (Annuel)', 'active', 150000, '2027-06-30'),
  ('sub-03', 'biz-03', 'STARTER', 'active', 5000, '2026-09-15'),
  ('sub-04', 'biz-04', 'GRATUIT (Essai)', 'expired', 0, '2026-07-01')
ON CONFLICT (id) DO NOTHING;

INSERT INTO staff_accounts (id, full_name, email, phone, role, status, current_lat, current_lng) VALUES
  ('st-01', 'Amadou Koné', 'kone@lynkstor.com', '+2250701020304', 'commercial', 'active', 5.3510, -4.0280),
  ('st-02', 'Sandrine Bamba', 'bamba@lynkstor.com', '+2250505060708', 'commercial', 'active', 5.3300, -4.0180),
  ('st-03', 'Marc Kouassi', 'kouassi@lynkstor.com', '+2250102030405', 'supervisor', 'active', NULL, NULL),
  ('st-04', 'Super Admin Lynkstor', 'admin@lynkstor.com', '+2250000000000', 'super_admin', 'active', NULL, NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO sales_summary (id, business_id, amount_fcfa, payment_method) VALUES
  ('s-1', 'biz-01', 125000, 'Espèces'),
  ('s-2', 'biz-01', 450000, 'Orange Money'),
  ('s-3', 'biz-02', 890000, 'MTN MoMo'),
  ('s-4', 'biz-03', 340000, 'Espèces'),
  ('s-5', 'biz-04', 620000, 'Wave')
ON CONFLICT (id) DO NOTHING;
