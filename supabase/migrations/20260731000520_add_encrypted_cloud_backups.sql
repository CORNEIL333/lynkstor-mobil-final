INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) VALUES (
  'kumba-backups',
  'kumba-backups',
  FALSE,
  104857600,
  ARRAY['application/octet-stream']
)
ON CONFLICT (id) DO UPDATE
  SET public = FALSE,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE TABLE IF NOT EXISTS public.cloud_backup_records (
  id TEXT PRIMARY KEY,
  business_id TEXT NOT NULL
    REFERENCES public.businesses(id) ON DELETE CASCADE,
  device_id TEXT,
  object_path TEXT NOT NULL UNIQUE,
  file_name TEXT NOT NULL,
  checksum TEXT NOT NULL CHECK (checksum ~ '^[0-9a-f]{64}$'),
  size_bytes BIGINT NOT NULL CHECK (
    size_bytes > 0 AND size_bytes <= 104857600
  ),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'available', 'failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  restored_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS cloud_backup_records_business_created_idx
  ON public.cloud_backup_records (business_id, created_at DESC);

ALTER TABLE public.cloud_backup_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.cloud_backup_records
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.cloud_backup_records
  TO service_role;
