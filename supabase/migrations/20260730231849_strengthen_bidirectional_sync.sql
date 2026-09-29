-- Bidirectional, cursor-based sync.
-- Mobile clients never access these tables directly: all traffic goes through
-- the lynkstor-api Edge Function using its server-side service_role client.

ALTER TABLE public.sync_events
  ADD COLUMN IF NOT EXISTS server_seq BIGINT GENERATED ALWAYS AS IDENTITY,
  ADD COLUMN IF NOT EXISTS device_id TEXT,
  ADD COLUMN IF NOT EXISTS client_created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS entity_version BIGINT NOT NULL DEFAULT 1;

CREATE UNIQUE INDEX IF NOT EXISTS sync_events_server_seq_key
  ON public.sync_events (server_seq);

CREATE INDEX IF NOT EXISTS sync_events_business_cursor_idx
  ON public.sync_events (business_id, server_seq);

CREATE TABLE IF NOT EXISTS public.sync_entities (
  business_id TEXT NOT NULL
    REFERENCES public.businesses(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL
    CHECK (operation IN ('create', 'update', 'delete', 'upsert')),
  payload_json JSONB NOT NULL DEFAULT '{}'::JSONB,
  entity_version BIGINT NOT NULL DEFAULT 1 CHECK (entity_version > 0),
  last_event_seq BIGINT NOT NULL
    REFERENCES public.sync_events(server_seq) ON DELETE RESTRICT,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (business_id, entity_type, entity_id)
);

CREATE INDEX IF NOT EXISTS sync_entities_business_updated_idx
  ON public.sync_entities (business_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.device_sync_cursors (
  business_id TEXT NOT NULL
    REFERENCES public.businesses(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  last_server_seq BIGINT NOT NULL DEFAULT 0 CHECK (last_server_seq >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (business_id, device_id)
);

CREATE INDEX IF NOT EXISTS device_sync_cursors_updated_idx
  ON public.device_sync_cursors (updated_at);

ALTER TABLE public.sync_entities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_sync_cursors ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.sync_entities, public.device_sync_cursors
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.sync_entities, public.device_sync_cursors
  TO service_role;
GRANT USAGE, SELECT
  ON SEQUENCE public.sync_events_server_seq_seq
  TO service_role;

CREATE OR REPLACE FUNCTION public.record_sync_event(
  p_event_id TEXT,
  p_business_id TEXT,
  p_entity_type TEXT,
  p_entity_id TEXT,
  p_operation TEXT,
  p_payload JSONB,
  p_entity_version BIGINT DEFAULT 1,
  p_device_id TEXT DEFAULT NULL,
  p_client_created_at TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  inserted_event public.sync_events%ROWTYPE;
  existing_event public.sync_events%ROWTYPE;
BEGIN
  IF p_operation NOT IN ('create', 'update', 'delete', 'upsert') THEN
    RAISE EXCEPTION 'INVALID_SYNC_OPERATION' USING ERRCODE = '22023';
  END IF;
  IF p_entity_version < 1 THEN
    RAISE EXCEPTION 'INVALID_ENTITY_VERSION' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.sync_events (
    id,
    business_id,
    entity_type,
    entity_id,
    operation,
    payload_json,
    device_id,
    client_created_at,
    entity_version
  ) VALUES (
    p_event_id,
    p_business_id,
    p_entity_type,
    p_entity_id,
    p_operation,
    COALESCE(p_payload, '{}'::JSONB),
    p_device_id,
    p_client_created_at,
    p_entity_version
  )
  ON CONFLICT (id) DO NOTHING
  RETURNING * INTO inserted_event;

  IF inserted_event.id IS NULL THEN
    SELECT *
      INTO existing_event
      FROM public.sync_events
     WHERE id = p_event_id;

    IF existing_event.business_id <> p_business_id
       OR existing_event.entity_type IS DISTINCT FROM p_entity_type
       OR existing_event.entity_id IS DISTINCT FROM p_entity_id
       OR existing_event.operation IS DISTINCT FROM p_operation
       OR existing_event.payload_json IS DISTINCT FROM COALESCE(
         p_payload,
         '{}'::JSONB
       ) THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;

    RETURN jsonb_build_object(
      'duplicate', TRUE,
      'id', existing_event.id,
      'serverSeq', existing_event.server_seq,
      'createdAt', existing_event.created_at
    );
  END IF;

  INSERT INTO public.sync_entities (
    business_id,
    entity_type,
    entity_id,
    operation,
    payload_json,
    entity_version,
    last_event_seq,
    is_deleted,
    updated_at
  ) VALUES (
    p_business_id,
    p_entity_type,
    p_entity_id,
    p_operation,
    COALESCE(p_payload, '{}'::JSONB),
    p_entity_version,
    inserted_event.server_seq,
    p_operation = 'delete',
    inserted_event.created_at
  )
  ON CONFLICT (business_id, entity_type, entity_id) DO UPDATE
    SET operation = EXCLUDED.operation,
        payload_json = EXCLUDED.payload_json,
        entity_version = EXCLUDED.entity_version,
        last_event_seq = EXCLUDED.last_event_seq,
        is_deleted = EXCLUDED.is_deleted,
        updated_at = EXCLUDED.updated_at
  WHERE EXCLUDED.entity_version > public.sync_entities.entity_version
     OR (
       EXCLUDED.entity_version = public.sync_entities.entity_version
       AND EXCLUDED.last_event_seq > public.sync_entities.last_event_seq
     );

  RETURN jsonb_build_object(
    'duplicate', FALSE,
    'id', inserted_event.id,
    'serverSeq', inserted_event.server_seq,
    'createdAt', inserted_event.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_sync_event(
  TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, BIGINT, TEXT, TIMESTAMPTZ
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_sync_event(
  TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, BIGINT, TEXT, TIMESTAMPTZ
) TO service_role;
