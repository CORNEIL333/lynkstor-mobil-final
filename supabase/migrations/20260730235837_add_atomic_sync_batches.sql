-- A whole mobile upload batch is committed or rolled back as one transaction.
CREATE OR REPLACE FUNCTION public.record_sync_batch(
  p_items JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  item JSONB;
  item_result JSONB;
  results JSONB := '[]'::JSONB;
  item_count INTEGER;
  sale_total NUMERIC;
  sale_methods TEXT;
BEGIN
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'SYNC_BATCH_MUST_BE_ARRAY' USING ERRCODE = '22023';
  END IF;

  item_count := jsonb_array_length(p_items);
  IF item_count < 1 OR item_count > 100 THEN
    RAISE EXCEPTION 'SYNC_BATCH_SIZE_INVALID' USING ERRCODE = '22023';
  END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    item_result := public.record_sync_event(
      item->>'id',
      item->>'businessId',
      item->>'entityType',
      item->>'entityId',
      item->>'operation',
      COALESCE(item->'payload', '{}'::JSONB),
      GREATEST(COALESCE((item->>'entityVersion')::BIGINT, 1), 1),
      NULLIF(item->>'deviceId', ''),
      NULLIF(item->>'localCreatedAt', '')::TIMESTAMPTZ
    );

    IF item->>'entityType' = 'sale'
       AND item->>'operation' IN ('create', 'upsert') THEN
      sale_total := (item->'payload'->>'total')::NUMERIC;
      IF sale_total < 0 THEN
        RAISE EXCEPTION 'INVALID_SALE_TOTAL' USING ERRCODE = '22023';
      END IF;
      SELECT COALESCE(string_agg(value, ', '), 'Non précisé')
        INTO sale_methods
        FROM jsonb_array_elements_text(
          COALESCE(item->'payload'->'paymentMethods', '[]'::JSONB)
        );
      INSERT INTO public.sales_summary (
        id, business_id, amount_fcfa, payment_method, sold_at
      ) VALUES (
        item->>'entityId',
        item->>'businessId',
        sale_total,
        sale_methods,
        COALESCE(
          NULLIF(item->'payload'->>'soldAt', '')::TIMESTAMPTZ,
          NOW()
        )
      )
      ON CONFLICT (id) DO UPDATE
        SET amount_fcfa = EXCLUDED.amount_fcfa,
            payment_method = EXCLUDED.payment_method,
            sold_at = EXCLUDED.sold_at;
    END IF;
    results := results || jsonb_build_array(item_result);
  END LOOP;

  RETURN jsonb_build_object('count', item_count, 'items', results);
END;
$$;

REVOKE ALL ON FUNCTION public.record_sync_batch(JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_sync_batch(JSONB) TO service_role;
