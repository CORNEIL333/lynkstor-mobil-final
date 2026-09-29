-- Security hardening: atomic registration and idempotent payment webhooks.

CREATE TABLE IF NOT EXISTS payment_webhook_events (
  id TEXT PRIMARY KEY,
  transaction_id TEXT NOT NULL UNIQUE,
  business_id TEXT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  payload_hash TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'processed'
    CHECK (status IN ('processed', 'ignored', 'failed')),
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_webhook_business_received
  ON payment_webhook_events (business_id, received_at DESC);

ALTER TABLE payment_webhook_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE payment_webhook_events FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE payment_webhook_events TO service_role;

ALTER TABLE device_sync_tokens
  ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;

-- Les fonctions Edge utilisent exclusivement service_role. Les droits sont
-- explicites pour rester sûrs avec les nouveaux projets Supabase qui ne
-- donnent plus automatiquement accès aux tables de l'API Data.
REVOKE ALL ON TABLE
  businesses, users, subscriptions, staff_accounts, field_activities,
  sync_events, sales_summary, registration_codes, device_sync_tokens
FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  businesses, users, subscriptions, staff_accounts, field_activities,
  sync_events, sales_summary, registration_codes, device_sync_tokens
TO service_role;

CREATE OR REPLACE FUNCTION public.register_business_atomic(
  p_code TEXT,
  p_business_id TEXT,
  p_business_name TEXT,
  p_owner_name TEXT,
  p_phone TEXT,
  p_sector TEXT,
  p_city TEXT,
  p_neighborhood TEXT,
  p_user_id TEXT,
  p_subscription_id TEXT,
  p_token_id TEXT,
  p_token_hash TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  reg registration_codes%ROWTYPE;
  expiry TIMESTAMPTZ;
BEGIN
  SELECT *
    INTO reg
    FROM registration_codes
   WHERE code = upper(trim(p_code))
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_CODE' USING ERRCODE = 'P0001';
  END IF;
  IF reg.status <> 'unused' THEN
    RAISE EXCEPTION 'CODE_USED' USING ERRCODE = 'P0001';
  END IF;
  IF reg.expires_at IS NOT NULL AND reg.expires_at < NOW() THEN
    RAISE EXCEPTION 'CODE_EXPIRED' USING ERRCODE = 'P0001';
  END IF;

  expiry := NOW() + make_interval(
    months => GREATEST(COALESCE(reg.duration_months, 1), 1)
  );

  INSERT INTO businesses (
    id, name, owner_name, phone, sector, city, neighborhood, status,
    registration_source, agent_staff_id, activation_code
  ) VALUES (
    p_business_id, trim(p_business_name), trim(p_owner_name), trim(p_phone),
    p_sector, p_city, p_neighborhood, 'active', 'agent', reg.staff_id, NULL
  );

  INSERT INTO users (
    id, business_id, full_name, phone, role, status, is_owner
  ) VALUES (
    p_user_id, p_business_id, trim(p_owner_name), trim(p_phone),
    'owner', 'active', TRUE
  );

  INSERT INTO subscriptions (
    id, business_id, plan_name, status, price_fcfa, expires_at
  ) VALUES (
    p_subscription_id, p_business_id, COALESCE(reg.plan_name, 'STARTER'),
    'active', COALESCE(reg.price_fcfa, 0), expiry
  );

  IF reg.staff_id IS NOT NULL THEN
    INSERT INTO field_activities (
      id, staff_id, business_id, activity_type,
      amount_collected_fcfa, notes
    ) VALUES (
      'act-' || replace(gen_random_uuid()::TEXT, '-', ''),
      reg.staff_id, p_business_id, 'activation',
      COALESCE(reg.price_fcfa, 0), 'Inscription application'
    );
  END IF;

  UPDATE registration_codes
     SET status = 'used',
         business_id = p_business_id,
         used_at = NOW()
   WHERE id = reg.id;

  INSERT INTO device_sync_tokens (id, business_id, token_hash, label)
  VALUES (p_token_id, p_business_id, p_token_hash, 'owner-device');

  RETURN jsonb_build_object(
    'planName', COALESCE(reg.plan_name, 'STARTER'),
    'priceFcfa', COALESCE(reg.price_fcfa, 0),
    'expiresAt', expiry,
    'staffId', reg.staff_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.register_business_atomic(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_business_atomic(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) TO service_role;

CREATE OR REPLACE FUNCTION public.process_payment_webhook(
  p_transaction_id TEXT,
  p_business_id TEXT,
  p_payload_hash TEXT,
  p_plan_name TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  new_expiry TIMESTAMPTZ;
BEGIN
  IF p_transaction_id IS NULL OR length(trim(p_transaction_id)) < 3 THEN
    RAISE EXCEPTION 'TRANSACTION_ID_REQUIRED' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO payment_webhook_events (
    id, transaction_id, business_id, payload_hash
  ) VALUES (
    'wh-' || replace(gen_random_uuid()::TEXT, '-', ''),
    trim(p_transaction_id), p_business_id, p_payload_hash
  )
  ON CONFLICT (transaction_id) DO NOTHING;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('duplicate', TRUE);
  END IF;

  UPDATE subscriptions
     SET status = 'active',
         plan_name = COALESCE(NULLIF(trim(p_plan_name), ''), plan_name),
         expires_at = GREATEST(COALESCE(expires_at, NOW()), NOW()) + INTERVAL '1 month'
   WHERE business_id = p_business_id
   RETURNING expires_at INTO new_expiry;

  IF new_expiry IS NULL THEN
    RAISE EXCEPTION 'SUBSCRIPTION_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object(
    'duplicate', FALSE,
    'expiresAt', new_expiry
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_payment_webhook(
  TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_payment_webhook(
  TEXT, TEXT, TEXT, TEXT
) TO service_role;
