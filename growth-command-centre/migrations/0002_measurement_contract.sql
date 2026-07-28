CREATE TABLE IF NOT EXISTS metric_definitions (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  kind TEXT NOT NULL,
  source_provider TEXT NOT NULL,
  calculation TEXT NOT NULL,
  unit TEXT NOT NULL,
  dimensions_json TEXT NOT NULL DEFAULT '[]',
  cadence TEXT NOT NULL DEFAULT 'daily',
  trust_level TEXT NOT NULL DEFAULT 'unavailable',
  status TEXT NOT NULL DEFAULT 'draft',
  owner_member_id TEXT REFERENCES members(id) ON DELETE SET NULL,
  version INTEGER NOT NULL DEFAULT 1,
  last_synced_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(workspace_id, name, version)
);

ALTER TABLE goals ADD COLUMN metric_definition_id TEXT REFERENCES metric_definitions(id);
ALTER TABLE metric_snapshots ADD COLUMN metric_definition_id TEXT REFERENCES metric_definitions(id);
ALTER TABLE metric_snapshots ADD COLUMN source_provider TEXT;
ALTER TABLE metric_snapshots ADD COLUMN trust_level TEXT NOT NULL DEFAULT 'unavailable';
ALTER TABLE metric_snapshots ADD COLUMN quality TEXT NOT NULL DEFAULT 'not_ready';

INSERT OR IGNORE INTO metric_definitions (
  id, workspace_id, name, description, kind, source_provider, calculation, unit,
  dimensions_json, cadence, trust_level, status, version, created_at, updated_at
)
SELECT
  'metric_' || id,
  workspace_id,
  metric_name,
  'Migrated metric definition. Connect and validate a source before using it for a live decision.',
  metric_kind,
  'workspace',
  'Migrated from the existing goal baseline.',
  unit,
  '[]',
  'daily',
  'unavailable',
  'needs_connection',
  1,
  created_at,
  updated_at
FROM goals
WHERE metric_definition_id IS NULL;

UPDATE goals
SET metric_definition_id = (
  SELECT id
  FROM metric_definitions
  WHERE metric_definitions.workspace_id = goals.workspace_id
    AND metric_definitions.name = goals.metric_name
    AND metric_definitions.version = 1
  ORDER BY created_at
  LIMIT 1
)
WHERE metric_definition_id IS NULL;

CREATE INDEX IF NOT EXISTS metric_definitions_workspace_idx ON metric_definitions(workspace_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS metric_snapshots_definition_idx ON metric_snapshots(metric_definition_id, captured_at DESC);
