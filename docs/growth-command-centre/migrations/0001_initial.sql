PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS workspaces (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  product_name TEXT NOT NULL,
  timezone TEXT NOT NULL DEFAULT 'UTC',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS members (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('admin', 'operator', 'viewer')),
  slack_user_id TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(workspace_id, email)
);

CREATE TABLE IF NOT EXISTS goals (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  metric_kind TEXT NOT NULL,
  metric_name TEXT NOT NULL,
  baseline REAL NOT NULL,
  target REAL NOT NULL,
  unit TEXT NOT NULL,
  deadline TEXT NOT NULL,
  guardrail TEXT,
  monthly_budget_cents INTEGER,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audiences (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  posthog_cohort_id TEXT,
  estimated_people INTEGER NOT NULL DEFAULT 0,
  consent_property TEXT NOT NULL,
  email_property TEXT NOT NULL,
  eligible INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS provider_connections (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  label TEXT NOT NULL,
  status TEXT NOT NULL,
  capabilities_json TEXT NOT NULL DEFAULT '[]',
  encrypted_config TEXT,
  last_synced_at TEXT,
  detail TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(workspace_id, provider)
);

CREATE TABLE IF NOT EXISTS experiments (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  surface TEXT NOT NULL,
  channel TEXT NOT NULL,
  status TEXT NOT NULL,
  hypothesis TEXT NOT NULL,
  channel_rationale TEXT NOT NULL,
  expected_impact TEXT NOT NULL,
  confidence REAL NOT NULL,
  audience_id TEXT REFERENCES audiences(id) ON DELETE SET NULL,
  optimization_metric TEXT NOT NULL,
  success_rule TEXT NOT NULL,
  decision_window_days INTEGER NOT NULL,
  variants_json TEXT NOT NULL,
  spend_json TEXT NOT NULL,
  engineering_flag_key TEXT,
  engineering_brief TEXT,
  approval_snapshot_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS learning_cards (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  experiment_id TEXT NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
  evidence_json TEXT NOT NULL,
  expected_impact TEXT NOT NULL,
  confidence REAL NOT NULL,
  outcome TEXT NOT NULL,
  outcome_summary TEXT NOT NULL,
  next_action TEXT NOT NULL,
  evaluated_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS engineering_briefs (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  experiment_id TEXT NOT NULL UNIQUE REFERENCES experiments(id) ON DELETE CASCADE,
  flag_key TEXT NOT NULL,
  variants_json TEXT NOT NULL,
  tracking_requirements_json TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS media_assets (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  kind TEXT NOT NULL,
  r2_key TEXT,
  external_url TEXT,
  prompt_summary TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS metric_snapshots (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  experiment_id TEXT REFERENCES experiments(id) ON DELETE CASCADE,
  source TEXT NOT NULL,
  metric_name TEXT NOT NULL,
  value REAL NOT NULL,
  dimensions_json TEXT NOT NULL DEFAULT '{}',
  captured_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS publications (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  experiment_id TEXT NOT NULL REFERENCES experiments(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  external_id TEXT,
  external_url TEXT,
  state TEXT NOT NULL,
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(experiment_id, provider)
);

CREATE TABLE IF NOT EXISTS execution_jobs (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  experiment_id TEXT REFERENCES experiments(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  approval_fingerprint TEXT,
  status TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(experiment_id, kind, approval_fingerprint)
);

CREATE TABLE IF NOT EXISTS slack_interactions (
  action_id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  slack_user_id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  received_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audit_events (
  id TEXT PRIMARY KEY,
  workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  actor_id TEXT,
  kind TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  detail_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS goals_workspace_idx ON goals(workspace_id, status);
CREATE INDEX IF NOT EXISTS experiments_workspace_idx ON experiments(workspace_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS learning_cards_experiment_idx ON learning_cards(experiment_id);
CREATE INDEX IF NOT EXISTS metric_snapshots_experiment_idx ON metric_snapshots(experiment_id, captured_at DESC);
CREATE INDEX IF NOT EXISTS audit_events_workspace_idx ON audit_events(workspace_id, created_at DESC);
