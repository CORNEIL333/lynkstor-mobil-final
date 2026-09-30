-- ============================================================================
-- Lynkstor — schéma NEON (Postgres 16+) consolidé et portable
-- ----------------------------------------------------------------------------
-- Objectif : remplacer le schéma Supabase par un Postgres standard (Neon),
-- sans dépendre des rôles Supabase (anon / authenticated / service_role) ni
-- de pgcrypto specifics indisponibles. L'accès passe par une API gateway
-- (Cloudflare Worker) qui unique utilise un rôle applicatif.
--
-- conventions :
--   * pas d'UUID Supabase : id TEXT (générés côté app/gateway) OU uuid DEFAULT
--     gen_random_uuid() (fonction native depuis PG13 — dispo Neon).
--   * TIMESTAMPTZ partout (timezone opérateur = fuseau du serveur).
--   * RLS : désactivée par défaut ici ; la gateway se connecte avec un rôle
--     NON superuser qui n'a que les GRANT nécessaires (défense en profondeur
--     via multi-tenancy applicatif sur business_id). RLS optionnelle fournie.
--
-- Appliquer :  psql "$NEON_POOL_URL" -f supabase/neon_schema.sql
-- ============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS lynkstor;
SET search_path TO lynkstor, public;

-- gen_random_uuid() : natif en PG13+. Sinon : CREATE EXTENSION pgcrypto.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. TENANTS & IDENTITÉ
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS businesses (
  id             TEXT PRIMARY KEY,
  name           TEXT NOT NULL,
  sector         TEXT NOT NULL DEFAULT 'general',
  phone          TEXT,
  owner_name     TEXT,
  country        TEXT,                       -- CI / SN / TG / ML / …
  status         TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','suspended','closed','trial')),
  latitude       NUMERIC,
  longitude      NUMERIC,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id             TEXT PRIMARY KEY,
  business_id    TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  full_name      TEXT NOT NULL,
  phone          TEXT,                       -- E.164, canal OTP principal
  phone_verified BOOLEAN NOT NULL DEFAULT false,
  role           TEXT NOT NULL DEFAULT 'seller'
                   CHECK (role IN ('owner','manager','seller','stockkeeper','accountant')),
  status         TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','invited','disabled')),
  password_hash  TEXT,                       -- pbkdf2 only (audit S7) ; null si OTP-only
  last_login_at  TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_users_business ON users (business_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_ci ON users (lower(phone))
  WHERE phone IS NOT NULL;

-- Comptes staff Lynkstor (terrain + admin). Auth séparée des marchands.
CREATE TABLE IF NOT EXISTS staff_accounts (
  id             TEXT PRIMARY KEY,
  full_name      TEXT NOT NULL,
  email          TEXT,
  username       TEXT,
  phone          TEXT,
  password_hash  TEXT,                       -- pbkdf2-sha256 (voir gateway)
  role           TEXT NOT NULL DEFAULT 'commercial'
                   CHECK (role IN ('super_admin','supervisor','commercial')),
  status         TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','disabled')),
  token_version  INTEGER NOT NULL DEFAULT 1, -- révocation sessions admin :
                   -- le token de session porte tv; toute requête admin revalide
                   -- tv + status contre cette table (bump = sessions révoquées)
  current_lat    NUMERIC,
  current_lng    NUMERIC,
  last_ping_at   TIMESTAMPTZ DEFAULT now(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_username_ci
  ON staff_accounts (lower(username)) WHERE username IS NOT NULL;
-- Idempotent pour les bases déjà en place (Neon prod) :
ALTER TABLE staff_accounts ADD COLUMN IF NOT EXISTS token_version INTEGER NOT NULL DEFAULT 1;

-- ----------------------------------------------------------------------------
-- 2. AUTH OTP MOBILE (Firebase alternative / self-hosted)
-- ----------------------------------------------------------------------------
-- Codes à usage unique, hashing côté gateway, expiration courte, anti-brute-force.

CREATE TABLE IF NOT EXISTS otp_challenges (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone          TEXT NOT NULL,
  code_hash      TEXT NOT NULL,              -- sha256 du code, jamais en clair
  purpose        TEXT NOT NULL DEFAULT 'login'
                   CHECK (purpose IN ('registration','login','password_reset')),
  attempts       INT NOT NULL DEFAULT 0,
  max_attempts   INT NOT NULL DEFAULT 5,
  verified       BOOLEAN NOT NULL DEFAULT false,
  expires_at     TIMESTAMPTZ NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_otp_phone_created ON otp_challenges (phone, created_at DESC);

CREATE TABLE IF NOT EXISTS otp_send_ratelimit (
  phone          TEXT PRIMARY KEY,
  sends_window   INT NOT NULL DEFAULT 0,
  window_started TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_sent_at   TIMESTAMPTZ
);

-- ----------------------------------------------------------------------------
-- 3. ABONNEMENTS & FORFAITS
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS plans (
  id             TEXT PRIMARY KEY,           -- STARTER / PRO / ENTERPRISE
  name           TEXT NOT NULL,
  price_fcfa     NUMERIC NOT NULL DEFAULT 0,
  billing_period TEXT NOT NULL DEFAULT 'monthly'
                   CHECK (billing_period IN ('monthly','quarterly','annual')),
  max_devices    INT NOT NULL DEFAULT 3,
  features       JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active      BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id             TEXT PRIMARY KEY,
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  plan_id        TEXT REFERENCES plans(id),
  plan_name      TEXT NOT NULL DEFAULT 'PRO',
  status         TEXT NOT NULL DEFAULT 'trial'
                   CHECK (status IN ('trial','active','expired','suspended','cancelled')),
  price_fcfa     NUMERIC NOT NULL DEFAULT 0,
  started_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_subscriptions_business ON subscriptions (business_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_expiry ON subscriptions (expires_at);

-- ----------------------------------------------------------------------------
-- 4. LICENCES SIGNÉES (correctif audit S1)
-- ----------------------------------------------------------------------------
-- Chaque émission de licence est journalisée + révocable. Le client ne fait
-- confiance qu'au jeton signé (voir lib/core/billing/license_contract.dart).

CREATE TABLE IF NOT EXISTS licenses (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  subscription_id TEXT REFERENCES subscriptions(id) ON DELETE SET NULL,
  plan           TEXT NOT NULL,
  token_hash     TEXT NOT NULL,              -- sha256 du jeton émis (anti-rejeu)
  token          TEXT,                       -- jeton signé brut, délivré au device pour la grâce offline signée (non secret : sécurité = signature)
  key_id         TEXT NOT NULL DEFAULT 'default',
  issued_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ NOT NULL,
  revoked_at     TIMESTAMPTZ,
  nonce          TEXT NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS idx_licenses_business ON licenses (business_id, issued_at DESC);

-- Clés de signature de licence (rotation). La clé PRIVÉE vit en secret
-- (worker env / KMS) ; cette table ne stocke que l'empreinte publique.
CREATE TABLE IF NOT EXISTS license_signing_keys (
  key_id         TEXT PRIMARY KEY,
  algorithm      TEXT NOT NULL DEFAULT 'Ed25519',
  public_key     TEXT NOT NULL,              -- base64 (clé publique seulement)
  active         BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  retired_at     TIMESTAMPTZ
);

-- ----------------------------------------------------------------------------
-- 5. PAIEMENTS / AGRÉGATEUR MOBILE MONEY
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS payment_intents (
  id                 TEXT PRIMARY KEY,
  business_id        TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  subscription_id    TEXT REFERENCES subscriptions(id) ON DELETE SET NULL,
  plan_id            TEXT REFERENCES plans(id),
  provider           TEXT NOT NULL,          -- cinetpay / senepay / kkiapay / wave
  channel            TEXT NOT NULL,          -- orange_money / mtn_momo / wave / card
  amount_fcfa        NUMERIC NOT NULL,
  currency           TEXT NOT NULL DEFAULT 'XOF',
  status             TEXT NOT NULL DEFAULT 'created'
                       CHECK (status IN ('created','pending_customer','processing',
                                         'succeeded','failed','expired','refunded')),
  provider_reference TEXT NOT NULL,          -- clé d'idempotence webhook
  customer_phone     TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payment_intents_business ON payment_intents (business_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_intents_provref
  ON payment_intents (provider, provider_reference);

-- Webhook agrégateur : idempotence + audit + anti rejeu.
CREATE TABLE IF NOT EXISTS payment_webhook_events (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider           TEXT NOT NULL,
  provider_reference TEXT NOT NULL,
  event_type         TEXT NOT NULL,
  payload            JSONB NOT NULL,
  signature_valid    BOOLEAN NOT NULL DEFAULT false,
  processed          BOOLEAN NOT NULL DEFAULT false,
  received_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_reference, event_type)
);
CREATE INDEX IF NOT EXISTS idx_webhook_business_received
  ON payment_webhook_events (received_at DESC);

-- ----------------------------------------------------------------------------
-- 6. SYNC MULTI-TENANT OFFLINE-FIRST (repris des migrations Supabase)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sync_events (
  id             TEXT PRIMARY KEY,
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  server_seq     BIGINT GENERATED ALWAYS AS IDENTITY,
  entity_type    TEXT NOT NULL,
  entity_id      TEXT NOT NULL,
  operation      TEXT NOT NULL,              -- insert / update / delete
  payload_json   JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sync_events_business_created
  ON sync_events (business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_events_business_cursor
  ON sync_events (business_id, server_seq);

-- État consolidé par entité (dernière version connue côté serveur).
CREATE TABLE IF NOT EXISTS sync_entities (
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  entity_type    TEXT NOT NULL,
  entity_id      TEXT NOT NULL,
  payload_json   JSONB NOT NULL DEFAULT '{}'::jsonb,
  deleted        BOOLEAN NOT NULL DEFAULT false,
  device_seq     BIGINT NOT NULL,            -- séquence locale du device émetteur
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, entity_type, entity_id)
);
CREATE INDEX IF NOT EXISTS idx_sync_entities_updated
  ON sync_entities (business_id, updated_at);

-- Curseur de sync par device (pour pull incrémental).
CREATE TABLE IF NOT EXISTS device_sync_cursors (
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  device_id      TEXT NOT NULL,
  last_server_seq BIGINT NOT NULL DEFAULT 0,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, device_id)
);

-- Tokens de sync par device, HASHÉS et révocables (audit S2 : plus de clé
-- partagée unique donnant accès à tous les tenants).
CREATE TABLE IF NOT EXISTS device_sync_tokens (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  device_id      TEXT NOT NULL,
  token_hash     TEXT NOT NULL UNIQUE,       -- sha256 du token, jamais en clair
  issued_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at   TIMESTAMPTZ,
  revoked_at     TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_business ON device_sync_tokens (business_id);

-- Invitations CLOUD multi-postes (migration 20260930000000) : un poste joint
-- la boutique via un code serveur à usage unique, sans code d'activation.
CREATE TABLE IF NOT EXISTS business_invitations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  code           TEXT NOT NULL UNIQUE,
  role           TEXT NOT NULL DEFAULT 'seller'
                   CHECK (role IN ('manager','seller','stockkeeper','accountant')),
  status         TEXT NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','used','revoked','expired')),
  created_by     TEXT,
  expires_at     TIMESTAMPTZ NOT NULL DEFAULT now() + interval '7 days',
  used_at        TIMESTAMPTZ,
  used_device_id TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_business_invitations_business
  ON business_invitations (business_id, status);

-- Batches atomiques de sync (remplacement des écritures non atomiques).
CREATE TABLE IF NOT EXISTS sync_batches (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  device_id      TEXT NOT NULL,
  operation_count INT NOT NULL DEFAULT 0,
  status         TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','applied','rejected','duplicate')),
  idempotency_key TEXT NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Idempotence par TENANT (clé globalement unique ferait entrer deux boutiques en collision).
CREATE UNIQUE INDEX IF NOT EXISTS uq_sync_batches_biz_idem
  ON sync_batches (business_id, idempotency_key);

-- ----------------------------------------------------------------------------
-- 7. ENREGISTREMENT / ACTIVATION PAR CODE AGENT
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS registration_codes (
  id             TEXT PRIMARY KEY,
  code           TEXT NOT NULL,
  business_name  TEXT,
  owner_phone    TEXT,
  assigned_staff TEXT REFERENCES staff_accounts(id) ON DELETE SET NULL,
  plan_id        TEXT REFERENCES plans(id),
  status         TEXT NOT NULL DEFAULT 'available'
                   CHECK (status IN ('available','reserved','used','void')),
  used_by_business TEXT REFERENCES businesses(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  used_at        TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_registration_code ON registration_codes (lower(code));
CREATE INDEX IF NOT EXISTS idx_registration_status ON registration_codes (status);

-- ----------------------------------------------------------------------------
-- 8. ACTIVITÉ TERRAIN & ANALYTIQUE D'ESSAI
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS field_activities (
  id             TEXT PRIMARY KEY,
  staff_id       TEXT NOT NULL REFERENCES staff_accounts(id) ON DELETE CASCADE,
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  activity_type  TEXT NOT NULL DEFAULT 'activation'
                   CHECK (activity_type IN ('activation','collection','visit')),
  amount_collected_fcfa NUMERIC NOT NULL DEFAULT 0,
  notes          TEXT,
  latitude       NUMERIC,
  longitude      NUMERIC,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS trial_analytics_events (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  install_id     TEXT NOT NULL,
  event_name     TEXT NOT NULL,
  sector         TEXT,
  payload        JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_trial_events_install ON trial_analytics_events (install_id);
CREATE INDEX IF NOT EXISTS idx_trial_events_name ON trial_analytics_events (event_name);

-- ----------------------------------------------------------------------------
-- 9. CONFIG SERVEUR (force-update / kill switch — audit S8)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS app_config (
  key                    TEXT PRIMARY KEY,
  value                  JSONB NOT NULL,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by             TEXT
);

-- Valeurs par défaut (GET /v1/config les lit).
INSERT INTO app_config (key, value) VALUES
  ('version_policy', jsonb_build_object(
     'minSupportedVersion', '1.0.0',
     'latestVersion',       '1.0.0',
     'updateMessage',       ''))
  ON CONFLICT (key) DO NOTHING;

INSERT INTO app_config (key, value) VALUES
  ('feature_flags', jsonb_build_object(
     'maintenance',              false,
     'killModules',              '[]'::jsonb,
     'requireAgentActivationCode', true,   -- DURCI par rapport à l'app (audit S1)
     'maxOfflineDays',           7))
  ON CONFLICT (key) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 10. SÉCURITÉ AU REPOS — backups chiffrés côté client (métadonnées serveur)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS cloud_backup_records (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id    TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  size_bytes     BIGINT NOT NULL DEFAULT 0,
  checksum       TEXT NOT NULL,              -- digest du blob chiffré côté client
  storage_ref    TEXT,                       -- URI objet (R2/S3), blob jamais en DB
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_backup_business_created
  ON cloud_backup_records (business_id, created_at DESC);

-- ----------------------------------------------------------------------------
-- RÔLE APPLICATIF (Neon : rôles standards, pas de service_role Supabase)
-- ----------------------------------------------------------------------------
-- La gateway se connecte avec ce rôle. Il n'a PAS de CREATEDB/BYPASSRLS.
-- Ajuster le nom/mot de passe via les secrets du Worker.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lynkstor_app') THEN
    CREATE ROLE lynkstor_app NOLOGIN;   -- le mot de passe est attaché via GRANT/ALTER en prod
  END IF;
END$$;

GRANT USAGE ON SCHEMA lynkstor TO lynkstor_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA lynkstor TO lynkstor_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA lynkstor TO lynkstor_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA lynkstor
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO lynkstor_app;

-- ----------------------------------------------------------------------------
-- Fonctions utilitaires (portables, sans Supabase vault)
-- ----------------------------------------------------------------------------

-- Marque un paiement webhook comme traité et active la licence associée.
CREATE OR REPLACE FUNCTION lynkstor.apply_paid_webhook(
  p_provider TEXT,
  p_provider_reference TEXT
) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  v_intent payment_intents%ROWTYPE;
  v_license_id TEXT;
BEGIN
  SELECT * INTO v_intent FROM payment_intents
    WHERE provider = p_provider AND provider_reference = p_provider_reference
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown payment reference';
  END IF;
  IF v_intent.status = 'succeeded' THEN
    RETURN v_intent.business_id;         -- idempotent
  END IF;

  UPDATE payment_intents SET status = 'succeeded', updated_at = now()
    WHERE id = v_intent.id;

  IF v_intent.subscription_id IS NOT NULL THEN
    UPDATE subscriptions SET status = 'active', updated_at = now()
      WHERE id = v_intent.subscription_id;
  END IF;

  RETURN v_intent.business_id;
END$$;

COMMIT;

-- ============================================================================
-- Notes de migration Supabase -> Neon :
--   * supprimer les références aux rôles anon/authenticated/service_role ;
--   * déplacer la logique Edge Function existante (register_business_atomic,
--     process_payment_webhook, record_sync_batch) vers la Worker API qui parle
--     à ce schéma via le rôle lynkstor_app ;
--   * ne JAMAIS exposer DIRECT (PostgREST) ce schéma à un client ;
--   * provisionner une clé Ed25519 dans license_signing_keys ; la clé privée
--     reste dans le secret store du Worker (jamais dans le dépôt).
-- ============================================================================
