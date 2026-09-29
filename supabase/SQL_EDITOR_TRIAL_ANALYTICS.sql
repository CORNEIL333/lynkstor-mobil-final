-- À coller dans le SQL Editor Supabase pour la période test.

CREATE TABLE IF NOT EXISTS trial_analytics_events (
  id TEXT PRIMARY KEY,
  install_id TEXT NOT NULL,
  business_id TEXT,
  sector TEXT,
  event_name TEXT NOT NULL,
  properties JSONB DEFAULT '{}'::jsonb,
  app_version TEXT,
  created_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trial_analytics_events_install
  ON trial_analytics_events (install_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_trial_analytics_events_name
  ON trial_analytics_events (event_name, created_at DESC);

CREATE TABLE IF NOT EXISTS trial_analytics_snapshots (
  id TEXT PRIMARY KEY,
  install_id TEXT NOT NULL,
  business_id TEXT,
  sector TEXT,
  sales_count INT DEFAULT 0,
  sold_fcfa NUMERIC DEFAULT 0,
  products_count INT DEFAULT 0,
  catalog_activated_count INT DEFAULT 0,
  customers_count INT DEFAULT 0,
  expenses_count INT DEFAULT 0,
  event_count INT DEFAULT 0,
  open_days INT DEFAULT 0,
  last_open_at TIMESTAMPTZ,
  app_version TEXT,
  captured_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_trial_analytics_snapshots_install
  ON trial_analytics_snapshots (install_id, captured_at DESC);

ALTER TABLE trial_analytics_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE trial_analytics_snapshots ENABLE ROW LEVEL SECURITY;
