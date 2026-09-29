-- Unifie les codes d'activation sur registration_codes, ajoute les
-- identifiants staff et rend l'inscription commerce rejouable après une
-- coupure réseau ou un échec SQLite local.

ALTER TABLE staff_accounts
  ADD COLUMN IF NOT EXISTS username TEXT,
  ADD COLUMN IF NOT EXISTS password_hash TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_accounts_username_ci
  ON staff_accounts (lower(username))
  WHERE username IS NOT NULL;

REVOKE ALL ON TABLE staff_accounts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE staff_accounts TO service_role;

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
  existing_user_id TEXT;
  existing_plan TEXT;
  existing_price NUMERIC;
  existing_expiry TIMESTAMPTZ;
BEGIN
  SELECT *
    INTO reg
    FROM registration_codes
   WHERE code = upper(trim(p_code))
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_CODE' USING ERRCODE = 'P0001';
  END IF;

  -- Une inscription dont la réponse réseau a été perdue peut être rejouée
  -- avec les mêmes identifiants préparés et conservés par l'application.
  IF reg.status = 'used' AND reg.business_id = p_business_id THEN
    SELECT id
      INTO existing_user_id
      FROM users
     WHERE business_id = p_business_id
       AND is_owner IS TRUE
     ORDER BY created_at
     LIMIT 1;

    SELECT plan_name, price_fcfa, expires_at
      INTO existing_plan, existing_price, existing_expiry
      FROM subscriptions
     WHERE business_id = p_business_id
     ORDER BY created_at DESC
     LIMIT 1;

    IF existing_user_id IS NULL OR existing_plan IS NULL THEN
      RAISE EXCEPTION 'REGISTRATION_INCOMPLETE' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO device_sync_tokens (id, business_id, token_hash, label)
    VALUES (p_token_id, p_business_id, p_token_hash, 'owner-device-recovery');

    RETURN jsonb_build_object(
      'businessId', p_business_id,
      'userId', existing_user_id,
      'planName', existing_plan,
      'priceFcfa', COALESCE(existing_price, 0),
      'expiresAt', existing_expiry,
      'staffId', reg.staff_id,
      'recovered', TRUE
    );
  END IF;

  IF reg.status = 'revoked' THEN
    RAISE EXCEPTION 'CODE_REVOKED' USING ERRCODE = 'P0001';
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
    'businessId', p_business_id,
    'userId', p_user_id,
    'planName', COALESCE(reg.plan_name, 'STARTER'),
    'priceFcfa', COALESCE(reg.price_fcfa, 0),
    'expiresAt', expiry,
    'staffId', reg.staff_id,
    'recovered', FALSE
  );
END;
$$;

REVOKE ALL ON FUNCTION public.register_business_atomic(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_business_atomic(
  TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) TO service_role;
