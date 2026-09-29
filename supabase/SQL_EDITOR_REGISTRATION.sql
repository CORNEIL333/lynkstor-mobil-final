-- À coller dans Supabase SQL Editor (si db push non utilisé)
-- Codes d'activation agent + jetons sync

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

ALTER TABLE businesses ADD COLUMN IF NOT EXISTS city TEXT;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS neighborhood TEXT;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS registration_source TEXT DEFAULT 'agent';
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS agent_staff_id TEXT;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS activation_code TEXT;

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_owner BOOLEAN DEFAULT false;

ALTER TABLE registration_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_sync_tokens ENABLE ROW LEVEL SECURITY;
