-- 20260930000000_cloud_business_invitations.sql
-- Invitations CLOUD multi-postes : un second appareil (poste) d'une même
-- boutique rejoint le business sans consommer de code d'activation agent.
-- Le code d'invitation est résolu côté serveur (plus dans le stockage local
-- de l'appareil hôte) et est à usage unique avec expiration.
SET search_path TO lynkstor,public;

CREATE TABLE IF NOT EXISTS business_invitations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  code           TEXT NOT NULL UNIQUE,
  role           TEXT NOT NULL DEFAULT 'seller'
                   CHECK (role IN ('manager','seller','stockkeeper','accountant')),
  status         TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','used','revoked','expired')),
  created_by     TEXT,                        -- user id du poste hôte
  expires_at     TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days',
  used_at        TIMESTAMPTZ,
  used_device_id TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_business_invitations_business
  ON business_invitations (business_id, status);
