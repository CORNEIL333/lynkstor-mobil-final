-- Lynkstor Business â€” schÃ©ma cloud Supabase
-- RLS fermÃ© pour anon ; accÃ¨s via Edge Function (service_role)

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

CREATE TABLE IF NOT EXISTS staff_accounts (
  id TEXT PRIMARY KEY,
  full_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  role TEXT CHECK (role IN ('super_admin', 'supervisor', 'commercial')) DEFAULT 'commercial',
  status TEXT DEFAULT 'active',
  current_lat NUMERIC,
  current_lng NUMERIC,
  last_ping_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS field_activities (
  id TEXT PRIMARY KEY,
  staff_id TEXT NOT NULL REFERENCES staff_accounts(id) ON DELETE CASCADE,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  activity_type TEXT CHECK (activity_type IN ('activation', 'collection', 'visit')) DEFAULT 'activation',
  amount_collected_fcfa NUMERIC DEFAULT 0,
  notes TEXT,
  latitude NUMERIC,
  longitude NUMERIC,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

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
  ON sync_events (business_id, created_at DESC);

CREATE TABLE IF NOT EXISTS sales_summary (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  amount_fcfa NUMERIC NOT NULL,
  payment_method TEXT DEFAULT 'EspÃ¨ces',
  sold_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS : aucun accÃ¨s direct anon/authenticated
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_summary ENABLE ROW LEVEL SECURITY;

-- Seed dÃ©mo
INSERT INTO businesses (id, name, sector, phone, owner_name, status, latitude, longitude) VALUES
  ('biz-01', 'Alimentation GÃ©nÃ©rale la GrÃ¢ce', 'epicerie', '+2250708091011', 'KouamÃ© Jean', 'active', 5.3484, -4.0305),
  ('biz-02', 'Pharmacie & Parfumerie du Centre', 'pharmacie', '+2250504030201', 'Dr. Aminata Diallo', 'active', 5.3261, -4.0211),
  ('biz-03', 'Boutique Quincaillerie Moderne', 'quincaillerie', '+221776543210', 'Mamadou Ndiaye', 'active', 5.3598, -3.9891),
  ('biz-04', 'DÃ©pÃ´t de Boissons le Jardin', 'grossiste', '+22890112233', 'Kofi Messan', 'active', 5.3712, -4.0150)
ON CONFLICT (id) DO NOTHING;

INSERT INTO users (id, business_id, full_name, phone, role, status) VALUES
  ('u-01', 'biz-01', 'KouamÃ© Jean', '+2250708091011', 'owner', 'active'),
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
  ('st-01', 'Amadou KonÃ©', 'kone@lynkstor.com', '+2250701020304', 'commercial', 'active', 5.3510, -4.0280),
  ('st-02', 'Sandrine Bamba', 'bamba@lynkstor.com', '+2250505060708', 'commercial', 'active', 5.3300, -4.0180),
  ('st-03', 'Marc Kouassi', 'kouassi@lynkstor.com', '+2250102030405', 'supervisor', 'active', NULL, NULL),
  ('st-04', 'Super Admin Lynkstor', 'admin@lynkstor.com', '+2250000000000', 'super_admin', 'active', NULL, NULL)
ON CONFLICT (id) DO NOTHING;

INSERT INTO field_activities (id, staff_id, business_id, activity_type, amount_collected_fcfa, notes, latitude, longitude) VALUES
  ('act-1', 'st-01', 'biz-01', 'activation', 15000, 'Abonnement PRO renouvelÃ©', 5.3484, -4.0305),
  ('act-2', 'st-02', 'biz-03', 'activation', 5000, 'STARTER encaissÃ© Wave', 5.3598, -3.9891)
ON CONFLICT (id) DO NOTHING;

INSERT INTO sales_summary (id, business_id, amount_fcfa, payment_method) VALUES
  ('s-1', 'biz-01', 125000, 'EspÃ¨ces'),
  ('s-2', 'biz-01', 450000, 'Orange Money'),
  ('s-3', 'biz-02', 890000, 'MTN MoMo'),
  ('s-4', 'biz-03', 340000, 'EspÃ¨ces'),
  ('s-5', 'biz-04', 620000, 'Wave')
ON CONFLICT (id) DO NOTHING;
-- Codes d'activation agent + jetons sync par commerce
-- Un client ne peut s'inscrire au cloud qu'avec un code fourni par un commercial.

CREATE TABLE IF NOT EXISTS registration_codes (
  id TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  staff_id TEXT REFERENCES staff_accounts(id) ON DELETE SET NULL,
  plan_name TEXT DEFAULT 'STARTER',
  price_fcfa NUMERIC DEFAULT 5000,
  duration_months INT DEFAULT 1,
  status TEXT CHECK (status IN ('unused', 'used', 'revoked')) DEFAULT 'unused',
  business_id TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  notes TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  used_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_registration_codes_code ON registration_codes (code);
CREATE INDEX IF NOT EXISTS idx_registration_codes_status ON registration_codes (status);

CREATE TABLE IF NOT EXISTS device_sync_tokens (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_sync_tokens_business ON device_sync_tokens (business_id);

-- Colonnes cloud sur businesses
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS neighborhood TEXT;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS registration_source TEXT DEFAULT 'agent';
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS agent_staff_id TEXT;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS activation_code TEXT;

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_owner BOOLEAN DEFAULT false;

ALTER TABLE registration_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_sync_tokens ENABLE ROW LEVEL SECURITY;
