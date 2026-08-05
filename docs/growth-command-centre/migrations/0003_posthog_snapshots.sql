ALTER TABLE metric_definitions ADD COLUMN source_metric_id TEXT;
ALTER TABLE provider_connections ADD COLUMN sync_error TEXT;

CREATE TABLE IF NOT EXISTS metric_sync_runs (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  status TEXT NOT NULL,
  watermark TEXT,
  error TEXT,
  started_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS metric_sync_runs_workspace_idx
  ON metric_sync_runs(workspace_id, provider, started_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS metric_snapshots_source_capture_idx
  ON metric_snapshots(workspace_id, metric_definition_id, source_provider, captured_at)
  WHERE metric_definition_id IS NOT NULL;
