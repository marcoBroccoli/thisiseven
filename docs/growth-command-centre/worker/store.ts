import { demoDashboard } from "./demo";
import { sourceFreshness } from "../shared/measurement";
import type {
  ApprovalSnapshot,
  AudienceDefinition,
  DataSource,
  DashboardPayload,
  EngineeringBrief,
  Experiment,
  ExperimentDraftUpdate,
  Goal,
  LearningCard,
  Member,
  MetricDefinition,
  MetricDefinitionInput,
  MetricSnapshot,
  ProviderConnection,
  Workspace
} from "../shared/types";

type Row = Record<string, unknown>;
const now = () => new Date().toISOString();
const id = (prefix: string) => `${prefix}_${crypto.randomUUID()}`;

function json<T>(value: unknown, fallback: T): T {
  if (typeof value !== "string") return fallback;
  try {
    return JSON.parse(value) as T;
  } catch {
    return fallback;
  }
}

function bool(value: unknown): boolean {
  return value === 1 || value === true || value === "1";
}

function workspaceFrom(row: Row): Workspace {
  return { id: String(row.id), name: String(row.name), productName: String(row.product_name), timezone: String(row.timezone) };
}

function memberFrom(row: Row): Member {
  return {
    id: String(row.id),
    name: String(row.name),
    email: String(row.email),
    role: row.role as Member["role"],
    slackUserId: typeof row.slack_user_id === "string" ? row.slack_user_id : undefined
  };
}

function goalFrom(row: Row): Goal {
  return {
    id: String(row.id),
    title: String(row.title),
    metricDefinitionId: typeof row.metric_definition_id === "string" ? row.metric_definition_id : undefined,
    metricKind: row.metric_kind as Goal["metricKind"],
    metricName: String(row.metric_name),
    baseline: Number(row.baseline),
    target: Number(row.target),
    unit: String(row.unit),
    deadline: String(row.deadline),
    guardrail: typeof row.guardrail === "string" ? row.guardrail : undefined,
    monthlyBudgetCents: typeof row.monthly_budget_cents === "number" ? row.monthly_budget_cents : undefined,
    status: row.status as Goal["status"]
  };
}

function metricDefinitionFrom(row: Row): MetricDefinition {
  return {
    id: String(row.id),
    name: String(row.name),
    description: String(row.description),
    kind: row.kind as MetricDefinition["kind"],
    sourceProvider: row.source_provider as MetricDefinition["sourceProvider"],
    calculation: String(row.calculation),
    sourceMetricId: typeof row.source_metric_id === "string" ? row.source_metric_id : undefined,
    unit: String(row.unit),
    dimensions: json(row.dimensions_json, []),
    cadence: row.cadence as MetricDefinition["cadence"],
    trustLevel: row.trust_level as MetricDefinition["trustLevel"],
    status: row.status as MetricDefinition["status"],
    ownerMemberId: typeof row.owner_member_id === "string" ? row.owner_member_id : undefined,
    version: Number(row.version),
    lastSyncedAt: typeof row.last_synced_at === "string" ? row.last_synced_at : undefined,
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at)
  };
}

function metricSnapshotFrom(row: Row): MetricSnapshot {
  return {
    id: String(row.id),
    metricDefinitionId: typeof row.metric_definition_id === "string" ? row.metric_definition_id : undefined,
    experimentId: typeof row.experiment_id === "string" ? row.experiment_id : undefined,
    sourceProvider: (typeof row.source_provider === "string" ? row.source_provider : row.source) as MetricSnapshot["sourceProvider"],
    value: Number(row.value),
    dimensions: json(row.dimensions_json, {}),
    trustLevel: row.trust_level as MetricSnapshot["trustLevel"],
    quality: row.quality as MetricSnapshot["quality"],
    capturedAt: String(row.captured_at)
  };
}

function audienceFrom(row: Row): AudienceDefinition {
  return {
    id: String(row.id),
    name: String(row.name),
    posthogCohortId: typeof row.posthog_cohort_id === "string" ? row.posthog_cohort_id : undefined,
    estimatedPeople: Number(row.estimated_people),
    consentProperty: String(row.consent_property),
    emailProperty: String(row.email_property),
    eligible: bool(row.eligible)
  };
}

function connectionFrom(row: Row): ProviderConnection {
  return {
    id: String(row.id),
    provider: row.provider as ProviderConnection["provider"],
    label: String(row.label),
    status: row.status as ProviderConnection["status"],
    capabilities: json(row.capabilities_json, []),
    lastSyncedAt: typeof row.last_synced_at === "string" ? row.last_synced_at : undefined,
    syncError: typeof row.sync_error === "string" ? row.sync_error : undefined,
    detail: String(row.detail)
  };
}

function dataSourcesFrom(connections: ProviderConnection[], sandboxMode: boolean): DataSource[] {
  const sources = connections
    .filter((connection) => connection.provider === "sandbox" || connection.provider === "posthog" || connection.capabilities.includes("read_channel_metrics"))
    .map((connection) => {
      const isSandbox = connection.provider === "sandbox";
      const canRead = connection.provider === "posthog"
        ? connection.capabilities.includes("read_analytics")
        : connection.capabilities.includes("read_channel_metrics");
      const trustLevel: DataSource["trustLevel"] = isSandbox ? "simulated" : !sandboxMode && connection.status === "connected" && canRead ? "observed" : "unavailable";
      const cadence: DataSource["cadence"] = "daily";
      const scope = isSandbox
        ? "Local workflow samples only"
        : connection.provider === "posthog"
          ? "Aggregate events, funnels, and cohorts"
          : "Aggregate delivery and channel reporting";
      return {
        id: `source_${connection.id}`,
        provider: connection.provider as DataSource["provider"],
        label: connection.label,
        status: connection.status,
        trustLevel,
        freshness: isSandbox ? "fresh" : sourceFreshness(connection.lastSyncedAt, cadence),
        lastSyncedAt: connection.lastSyncedAt,
        syncError: connection.syncError,
        cadence,
        scope,
        detail: isSandbox
          ? "Simulated results exercise the workflow but never change production totals."
          : sandboxMode
            ? "Sandbox mode prevents this connection from being treated as a live measurement source."
            : connection.detail
      };
    });
  if (sandboxMode && !sources.some((source) => source.provider === "sandbox")) {
    sources.unshift({
      id: "source_sandbox",
      provider: "sandbox",
      label: "Built-in Sandbox",
      status: "connected",
      trustLevel: "simulated",
      freshness: "fresh",
      lastSyncedAt: undefined,
      syncError: undefined,
      cadence: "daily",
      scope: "Local workflow samples only",
      detail: "Simulated results exercise the workflow but never change production totals."
    });
  }
  sources.push({
    id: "source_workspace",
    provider: "workspace",
    label: "Workspace records",
    status: "not_connected",
    trustLevel: "unavailable",
    freshness: "not_synced",
    lastSyncedAt: undefined,
    syncError: undefined,
    cadence: "daily",
    scope: "Planning baselines and migrated goal records",
    detail: "Workspace records provide context, not a verified measurement. Connect a measurement source before using them for a live decision."
  });
  return sources;
}

function experimentFrom(row: Row): Experiment {
  return {
    id: String(row.id),
    goalId: String(row.goal_id),
    title: String(row.title),
    surface: row.surface as Experiment["surface"],
    channel: row.channel as Experiment["channel"],
    status: row.status as Experiment["status"],
    hypothesis: String(row.hypothesis),
    channelRationale: String(row.channel_rationale),
    expectedImpact: row.expected_impact as Experiment["expectedImpact"],
    confidence: Number(row.confidence),
    audienceId: typeof row.audience_id === "string" ? row.audience_id : undefined,
    optimizationMetric: String(row.optimization_metric),
    successRule: String(row.success_rule),
    decisionWindowDays: Number(row.decision_window_days),
    variants: json(row.variants_json, []),
    spend: json(row.spend_json, {}),
    engineeringFlagKey: typeof row.engineering_flag_key === "string" ? row.engineering_flag_key : undefined,
    engineeringBrief: typeof row.engineering_brief === "string" ? row.engineering_brief : undefined,
    approvalSnapshot: json<ApprovalSnapshot | undefined>(row.approval_snapshot_json, undefined),
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at)
  };
}

function cardFrom(row: Row): LearningCard {
  return {
    id: String(row.id),
    experimentId: String(row.experiment_id),
    evidence: json(row.evidence_json, []),
    expectedImpact: row.expected_impact as LearningCard["expectedImpact"],
    confidence: Number(row.confidence),
    outcome: row.outcome as LearningCard["outcome"],
    outcomeSummary: String(row.outcome_summary),
    nextAction: String(row.next_action),
    evaluatedAt: typeof row.evaluated_at === "string" ? row.evaluated_at : undefined
  };
}

function briefFrom(row: Row): EngineeringBrief {
  return {
    id: String(row.id),
    experimentId: String(row.experiment_id),
    flagKey: String(row.flag_key),
    variants: json(row.variants_json, []),
    trackingRequirements: json(row.tracking_requirements_json, []),
    status: row.status as EngineeringBrief["status"]
  };
}

async function rows(db: D1Database, query: string, ...values: unknown[]): Promise<Row[]> {
  const result = await db.prepare(query).bind(...values).all<Row>();
  return result.results ?? [];
}

async function first(db: D1Database, query: string, ...values: unknown[]): Promise<Row | undefined> {
  return (await rows(db, query, ...values))[0];
}

export async function ensureDemoSeed(db: D1Database): Promise<void> {
  const existing = await first(db, "SELECT id FROM workspaces LIMIT 1");
  if (existing) return;

  const state = demoDashboard;
  const timestamp = now();
  const statements: D1PreparedStatement[] = [
    db.prepare("INSERT INTO workspaces (id, name, product_name, timezone, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(state.workspace.id, state.workspace.name, state.workspace.productName, state.workspace.timezone, timestamp),
    db.prepare("INSERT INTO members (id, workspace_id, name, email, role, slack_user_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .bind(state.me.id, state.workspace.id, state.me.name, state.me.email, state.me.role, state.me.slackUserId ?? null, timestamp)
  ];

  for (const metric of state.metricDefinitions) {
    statements.push(
      db.prepare(`INSERT INTO metric_definitions (id, workspace_id, name, description, kind, source_provider, calculation, unit, dimensions_json, cadence, trust_level, status, owner_member_id, version, last_synced_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(metric.id, state.workspace.id, metric.name, metric.description, metric.kind, metric.sourceProvider, metric.calculation, metric.unit, JSON.stringify(metric.dimensions), metric.cadence, metric.trustLevel, metric.status, metric.ownerMemberId ?? null, metric.version, metric.lastSyncedAt ?? null, metric.createdAt, metric.updatedAt)
    );
  }
  for (const goal of state.goals) {
    statements.push(
      db.prepare(`INSERT INTO goals (id, workspace_id, title, metric_definition_id, metric_kind, metric_name, baseline, target, unit, deadline, guardrail, monthly_budget_cents, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(goal.id, state.workspace.id, goal.title, goal.metricDefinitionId ?? null, goal.metricKind, goal.metricName, goal.baseline, goal.target, goal.unit, goal.deadline, goal.guardrail ?? null, goal.monthlyBudgetCents ?? null, goal.status, timestamp, timestamp)
    );
  }
  for (const audience of state.audiences) {
    statements.push(
      db.prepare("INSERT INTO audiences (id, workspace_id, name, posthog_cohort_id, estimated_people, consent_property, email_property, eligible, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
        .bind(audience.id, state.workspace.id, audience.name, audience.posthogCohortId ?? null, audience.estimatedPeople, audience.consentProperty, audience.emailProperty, audience.eligible ? 1 : 0, timestamp)
    );
  }
  for (const connection of state.connections) {
    statements.push(
      db.prepare(`INSERT INTO provider_connections (id, workspace_id, provider, label, status, capabilities_json, detail, last_synced_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(connection.id, state.workspace.id, connection.provider, connection.label, connection.status, JSON.stringify(connection.capabilities), connection.detail, connection.lastSyncedAt ?? null, timestamp, timestamp)
    );
  }
  for (const experiment of state.experiments) {
    statements.push(experimentStatement(db, state.workspace.id, experiment));
  }
  for (const card of state.learningCards) {
    statements.push(
      db.prepare(`INSERT INTO learning_cards (id, workspace_id, experiment_id, evidence_json, expected_impact, confidence, outcome, outcome_summary, next_action, evaluated_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(card.id, state.workspace.id, card.experimentId, JSON.stringify(card.evidence), card.expectedImpact, card.confidence, card.outcome, card.outcomeSummary, card.nextAction, card.evaluatedAt ?? null, timestamp)
    );
  }
  for (const snapshot of state.metricSnapshots) {
    const metric = state.metricDefinitions.find((item) => item.id === snapshot.metricDefinitionId);
    statements.push(
      db.prepare(`INSERT INTO metric_snapshots (id, workspace_id, experiment_id, source, metric_name, value, dimensions_json, captured_at, metric_definition_id, source_provider, trust_level, quality)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(snapshot.id, state.workspace.id, snapshot.experimentId ?? null, snapshot.sourceProvider, metric?.name ?? "Unmapped metric", snapshot.value, JSON.stringify(snapshot.dimensions), snapshot.capturedAt, snapshot.metricDefinitionId ?? null, snapshot.sourceProvider, snapshot.trustLevel, snapshot.quality)
    );
  }
  for (const brief of state.engineeringBriefs) {
    statements.push(
      db.prepare(`INSERT INTO engineering_briefs (id, workspace_id, experiment_id, flag_key, variants_json, tracking_requirements_json, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(brief.id, state.workspace.id, brief.experimentId, brief.flagKey, JSON.stringify(brief.variants), JSON.stringify(brief.trackingRequirements), brief.status, timestamp, timestamp)
    );
  }
  await db.batch(statements);
}

function experimentStatement(db: D1Database, workspaceId: string, experiment: Experiment): D1PreparedStatement {
  return db.prepare(`INSERT INTO experiments (id, workspace_id, goal_id, title, surface, channel, status, hypothesis, channel_rationale, expected_impact, confidence, audience_id, optimization_metric, success_rule, decision_window_days, variants_json, spend_json, engineering_flag_key, engineering_brief, approval_snapshot_json, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(
      experiment.id, workspaceId, experiment.goalId, experiment.title, experiment.surface, experiment.channel, experiment.status,
      experiment.hypothesis, experiment.channelRationale, experiment.expectedImpact, experiment.confidence, experiment.audienceId ?? null,
      experiment.optimizationMetric, experiment.successRule, experiment.decisionWindowDays, JSON.stringify(experiment.variants), JSON.stringify(experiment.spend),
      experiment.engineeringFlagKey ?? null, experiment.engineeringBrief ?? null, experiment.approvalSnapshot ? JSON.stringify(experiment.approvalSnapshot) : null,
      experiment.createdAt, experiment.updatedAt
    );
}

export async function loadDashboard(db: D1Database, sandboxMode = false): Promise<DashboardPayload> {
  await ensureDemoSeed(db);
  const workspaceRow = await first(db, "SELECT * FROM workspaces ORDER BY created_at LIMIT 1");
  if (!workspaceRow) throw new Error("Workspace seed failed.");
  const workspace = workspaceFrom(workspaceRow);
  const [memberRow, goalRows, experimentRows, cardRows, connectionRows, metricRows, snapshotRows, audienceRows, briefRows] = await Promise.all([
    first(db, "SELECT * FROM members WHERE workspace_id = ? ORDER BY CASE role WHEN 'admin' THEN 0 ELSE 1 END LIMIT 1", workspace.id),
    rows(db, "SELECT * FROM goals WHERE workspace_id = ? ORDER BY deadline", workspace.id),
    rows(db, "SELECT * FROM experiments WHERE workspace_id = ? ORDER BY updated_at DESC", workspace.id),
    rows(db, "SELECT * FROM learning_cards WHERE workspace_id = ? ORDER BY created_at DESC", workspace.id),
    rows(db, "SELECT * FROM provider_connections WHERE workspace_id = ? ORDER BY provider", workspace.id),
    rows(db, "SELECT * FROM metric_definitions WHERE workspace_id = ? ORDER BY updated_at DESC", workspace.id),
    rows(db, "SELECT * FROM metric_snapshots WHERE workspace_id = ? ORDER BY captured_at DESC LIMIT 500", workspace.id),
    rows(db, "SELECT * FROM audiences WHERE workspace_id = ? ORDER BY name", workspace.id),
    rows(db, "SELECT * FROM engineering_briefs WHERE workspace_id = ? ORDER BY created_at DESC", workspace.id)
  ]);
  if (!memberRow) throw new Error("No workspace member exists.");
  const monitor = await first(db, "SELECT created_at FROM audit_events WHERE workspace_id = ? AND kind = 'daily_monitor_completed' ORDER BY created_at DESC LIMIT 1", workspace.id);
  const plan = await first(db, "SELECT created_at FROM audit_events WHERE workspace_id = ? AND kind = 'weekly_plan_completed' ORDER BY created_at DESC LIMIT 1", workspace.id);
  const connections = connectionRows.map(connectionFrom);
  return {
    workspace,
    me: memberFrom(memberRow),
    goals: goalRows.map(goalFrom),
    experiments: experimentRows.map(experimentFrom),
    learningCards: cardRows.map(cardFrom),
    connections,
    dataSources: dataSourcesFrom(connections, sandboxMode),
    metricDefinitions: metricRows.map(metricDefinitionFrom),
    metricSnapshots: snapshotRows.map(metricSnapshotFrom),
    audiences: audienceRows.map(audienceFrom),
    engineeringBriefs: briefRows.map(briefFrom),
    sandboxMode,
    lastDailyMonitorAt: typeof monitor?.created_at === "string" ? monitor.created_at : undefined,
    lastWeeklyPlanAt: typeof plan?.created_at === "string" ? plan.created_at : undefined
  };
}

export async function createGoal(db: D1Database, workspaceId: string, input: Omit<Goal, "id" | "status">, actorId: string): Promise<Goal> {
  const goal: Goal = { id: id("goal"), ...input, status: "active" };
  const timestamp = now();
  await db.batch([
    db.prepare(`INSERT INTO goals (id, workspace_id, title, metric_definition_id, metric_kind, metric_name, baseline, target, unit, deadline, guardrail, monthly_budget_cents, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(goal.id, workspaceId, goal.title, goal.metricDefinitionId ?? null, goal.metricKind, goal.metricName, goal.baseline, goal.target, goal.unit, goal.deadline, goal.guardrail ?? null, goal.monthlyBudgetCents ?? null, goal.status, timestamp, timestamp),
    auditStatement(db, workspaceId, actorId, "goal_created", "goal", goal.id, { title: goal.title })
  ]);
  return goal;
}

export async function metricDefinitionFor(db: D1Database, workspaceId: string, metricDefinitionId: string): Promise<MetricDefinition | undefined> {
  const row = await first(db, "SELECT * FROM metric_definitions WHERE workspace_id = ? AND id = ?", workspaceId, metricDefinitionId);
  return row ? metricDefinitionFrom(row) : undefined;
}

export async function createMetricDefinition(db: D1Database, workspaceId: string, input: MetricDefinitionInput, actorId: string): Promise<MetricDefinition> {
  const timestamp = now();
  const connection = input.sourceProvider === "workspace" ? undefined : await connectionFor(db, workspaceId, input.sourceProvider);
  const supportsRead = input.sourceProvider === "posthog"
    ? connection?.capabilities.includes("read_analytics")
    : connection?.capabilities.includes("read_channel_metrics");
  const trustLevel: MetricDefinition["trustLevel"] = input.sourceProvider === "sandbox" ? "simulated" : connection?.status === "connected" && supportsRead ? "observed" : "unavailable";
  const sourceIsMapped = input.sourceProvider !== "posthog" || Boolean(input.sourceMetricId);
  const status: MetricDefinition["status"] = input.sourceProvider === "sandbox" || trustLevel === "observed" && sourceIsMapped
    ? "ready"
    : input.sourceProvider === "workspace" || connection?.status === "connected"
      ? "draft"
      : "needs_connection";
  const metric: MetricDefinition = {
    id: id("metric"),
    ...input,
    trustLevel,
    status,
    ownerMemberId: actorId,
    version: 1,
    createdAt: timestamp,
    updatedAt: timestamp
  };
  await db.batch([
    db.prepare(`INSERT INTO metric_definitions (id, workspace_id, name, description, kind, source_provider, calculation, source_metric_id, unit, dimensions_json, cadence, trust_level, status, owner_member_id, version, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(metric.id, workspaceId, metric.name, metric.description, metric.kind, metric.sourceProvider, metric.calculation, metric.sourceMetricId ?? null, metric.unit, JSON.stringify(metric.dimensions), metric.cadence, metric.trustLevel, metric.status, actorId, metric.version, timestamp, timestamp),
    auditStatement(db, workspaceId, actorId, "metric_definition_created", "metric_definition", metric.id, { sourceProvider: metric.sourceProvider, trustLevel: metric.trustLevel, status: metric.status })
  ]);
  return metric;
}

export async function createMetricSnapshot(db: D1Database, workspaceId: string, snapshot: MetricSnapshot): Promise<boolean> {
  const metric = snapshot.metricDefinitionId ? await metricDefinitionFor(db, workspaceId, snapshot.metricDefinitionId) : undefined;
  const result = await db.prepare(`INSERT OR IGNORE INTO metric_snapshots (id, workspace_id, experiment_id, source, metric_name, value, dimensions_json, captured_at, metric_definition_id, source_provider, trust_level, quality)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(snapshot.id, workspaceId, snapshot.experimentId ?? null, snapshot.sourceProvider, metric?.name ?? "Unmapped metric", snapshot.value, JSON.stringify(snapshot.dimensions), snapshot.capturedAt, snapshot.metricDefinitionId ?? null, snapshot.sourceProvider, snapshot.trustLevel, snapshot.quality).run();
  return result.meta.changes > 0;
}

export async function getExperiment(db: D1Database, experimentId: string): Promise<{ experiment: Experiment; workspaceId: string } | undefined> {
  const row = await first(db, "SELECT * FROM experiments WHERE id = ?", experimentId);
  return row ? { experiment: experimentFrom(row), workspaceId: String(row.workspace_id) } : undefined;
}

export async function updateExperimentDraft(db: D1Database, experimentId: string, update: ExperimentDraftUpdate, actorId: string): Promise<Experiment> {
  const existing = await getExperiment(db, experimentId);
  if (!existing) throw new Error("Experiment was not found.");
  const editableStatuses: Experiment["status"][] = ["proposed", "needs_changes", "awaiting_approval", "blocked"];
  if (!editableStatuses.includes(existing.experiment.status)) {
    throw new Error("Only a proposal that has not started can be edited.");
  }
  const timestamp = now();
  await db.batch([
    db.prepare(`UPDATE experiments
      SET hypothesis = ?, audience_id = ?, success_rule = ?, decision_window_days = ?, variants_json = ?, spend_json = ?, updated_at = ?
      WHERE id = ?`)
      .bind(update.hypothesis, update.audienceId ?? null, update.successRule, update.decisionWindowDays, JSON.stringify(update.variants), JSON.stringify(update.spend), timestamp, experimentId),
    auditStatement(db, existing.workspaceId, actorId, "experiment_draft_edited", "experiment", experimentId, {
      audienceId: update.audienceId ?? null,
      decisionWindowDays: update.decisionWindowDays,
      variantCount: update.variants.length,
      hasPaidSpend: Boolean(update.spend.dailyCents || update.spend.totalCents)
    })
  ]);
  return { ...existing.experiment, ...update, updatedAt: timestamp };
}

export async function connectionFor(db: D1Database, workspaceId: string, provider: ProviderConnection["provider"]): Promise<ProviderConnection | undefined> {
  const row = await first(db, "SELECT * FROM provider_connections WHERE workspace_id = ? AND provider = ?", workspaceId, provider);
  return row ? connectionFrom(row) : undefined;
}

export async function storeConnectionConfig(
  db: D1Database,
  workspaceId: string,
  provider: ProviderConnection["provider"],
  encryptedConfig: string,
  actorId: string
): Promise<void> {
  const connection = await connectionFor(db, workspaceId, provider);
  if (!connection) throw new Error("Provider is not registered for this workspace.");
  await db.batch([
    db.prepare("UPDATE provider_connections SET encrypted_config = ?, updated_at = ? WHERE id = ?")
      .bind(encryptedConfig, now(), connection.id),
    auditStatement(db, workspaceId, actorId, "connection_configured", "provider_connection", connection.id, { provider })
  ]);
}

export async function encryptedConnectionConfig(
  db: D1Database,
  workspaceId: string,
  provider: ProviderConnection["provider"]
): Promise<string | undefined> {
  const row = await first(db, "SELECT encrypted_config FROM provider_connections WHERE workspace_id = ? AND provider = ?", workspaceId, provider);
  return typeof row?.encrypted_config === "string" ? row.encrypted_config : undefined;
}

export async function markConnectionVerified(
  db: D1Database,
  workspaceId: string,
  provider: ProviderConnection["provider"],
  capabilities: ProviderConnection["capabilities"],
  detail: string,
  actorId: string
): Promise<void> {
  const connection = await connectionFor(db, workspaceId, provider);
  if (!connection) throw new Error("Provider is not registered for this workspace.");
  const timestamp = now();
  await db.batch([
    db.prepare("UPDATE provider_connections SET status = 'connected', capabilities_json = ?, detail = ?, sync_error = NULL, updated_at = ? WHERE id = ?")
      .bind(JSON.stringify(capabilities), detail, timestamp, connection.id),
    db.prepare(`UPDATE metric_definitions
      SET trust_level = 'observed', status = CASE
        WHEN source_provider = 'posthog' AND (source_metric_id IS NULL OR source_metric_id = '') THEN 'draft'
        ELSE 'ready'
      END, updated_at = ?
      WHERE workspace_id = ? AND source_provider = ?`)
      .bind(timestamp, workspaceId, provider),
    auditStatement(db, workspaceId, actorId, "connection_verified", "provider_connection", connection.id, { provider, capabilities })
  ]);
}

export async function recordConnectionSync(
  db: D1Database,
  workspaceId: string,
  provider: ProviderConnection["provider"],
  error?: string
): Promise<void> {
  const timestamp = now();
  if (error) {
    await db.prepare("UPDATE provider_connections SET sync_error = ?, updated_at = ? WHERE workspace_id = ? AND provider = ?")
      .bind(error, timestamp, workspaceId, provider).run();
    return;
  }
  await db.prepare("UPDATE provider_connections SET last_synced_at = ?, sync_error = NULL, updated_at = ? WHERE workspace_id = ? AND provider = ?")
    .bind(timestamp, timestamp, workspaceId, provider).run();
}

export async function markMetricSynced(db: D1Database, workspaceId: string, metricDefinitionId: string, capturedAt: string): Promise<void> {
  await db.prepare("UPDATE metric_definitions SET last_synced_at = ?, updated_at = ? WHERE workspace_id = ? AND id = ?")
    .bind(capturedAt, now(), workspaceId, metricDefinitionId).run();
}

export async function startMetricSyncRun(
  db: D1Database,
  workspaceId: string,
  provider: ProviderConnection["provider"],
  watermark: string
): Promise<string> {
  const syncRunId = id("sync");
  await db.prepare("INSERT INTO metric_sync_runs (id, workspace_id, provider, status, watermark, started_at) VALUES (?, ?, ?, 'running', ?, ?)")
    .bind(syncRunId, workspaceId, provider, watermark, now()).run();
  return syncRunId;
}

export async function finishMetricSyncRun(db: D1Database, syncRunId: string, error?: string): Promise<void> {
  await db.prepare("UPDATE metric_sync_runs SET status = ?, error = ?, completed_at = ? WHERE id = ?")
    .bind(error ? "failed" : "completed", error ?? null, now(), syncRunId).run();
}

export async function metricSnapshotsFor(
  db: D1Database,
  workspaceId: string,
  metricDefinitionId: string,
  limit = 90
): Promise<MetricSnapshot[]> {
  const snapshotRows = await rows(
    db,
    "SELECT * FROM metric_snapshots WHERE workspace_id = ? AND metric_definition_id = ? ORDER BY captured_at DESC LIMIT ?",
    workspaceId,
    metricDefinitionId,
    Math.min(Math.max(limit, 1), 365)
  );
  return snapshotRows.map(metricSnapshotFrom);
}

export async function audienceFor(db: D1Database, audienceId?: string): Promise<AudienceDefinition | undefined> {
  if (!audienceId) return undefined;
  const row = await first(db, "SELECT * FROM audiences WHERE id = ?", audienceId);
  return row ? audienceFrom(row) : undefined;
}

export async function engineeringFlagRegistered(db: D1Database, experimentId: string): Promise<boolean> {
  const row = await first(db, "SELECT status FROM engineering_briefs WHERE experiment_id = ?", experimentId);
  return row?.status === "registered";
}

export async function approveExperiment(
  db: D1Database,
  workspaceId: string,
  experiment: Experiment,
  snapshot: ApprovalSnapshot,
  actorId: string
): Promise<void> {
  const timestamp = now();
  await db.batch([
    db.prepare("UPDATE experiments SET status = 'approved', approval_snapshot_json = ?, updated_at = ? WHERE id = ?")
      .bind(JSON.stringify(snapshot), timestamp, experiment.id),
    auditStatement(db, workspaceId, actorId, "experiment_approved", "experiment", experiment.id, { fingerprint: snapshot.fingerprint })
  ]);
}

export async function createExperiment(db: D1Database, workspaceId: string, experiment: Experiment, actorId: string): Promise<void> {
  await db.batch([
    experimentStatement(db, workspaceId, experiment),
    auditStatement(db, workspaceId, actorId, "experiment_proposed", "experiment", experiment.id, { channel: experiment.channel })
  ]);
}

export async function createLearningCard(db: D1Database, workspaceId: string, card: LearningCard): Promise<void> {
  await db.prepare(`INSERT INTO learning_cards (id, workspace_id, experiment_id, evidence_json, expected_impact, confidence, outcome, outcome_summary, next_action, evaluated_at, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(card.id, workspaceId, card.experimentId, JSON.stringify(card.evidence), card.expectedImpact, card.confidence, card.outcome, card.outcomeSummary, card.nextAction, card.evaluatedAt ?? null, now()).run();
}

export async function transitionExperiment(db: D1Database, experimentId: string, status: Experiment["status"], actorId: string, kind: string): Promise<void> {
  const existing = await getExperiment(db, experimentId);
  if (!existing) throw new Error("Experiment was not found.");
  await db.batch([
    db.prepare("UPDATE experiments SET status = ?, updated_at = ? WHERE id = ?").bind(status, now(), experimentId),
    auditStatement(db, existing.workspaceId, actorId, kind, "experiment", experimentId, { status })
  ]);
}

export async function registerSlackInteraction(db: D1Database, actionId: string, workspaceId: string, slackUserId: string, payload: unknown): Promise<boolean> {
  const existing = await first(db, "SELECT action_id FROM slack_interactions WHERE action_id = ?", actionId);
  if (existing) return false;
  await db.prepare("INSERT INTO slack_interactions (action_id, workspace_id, slack_user_id, payload_json, received_at) VALUES (?, ?, ?, ?, ?)")
    .bind(actionId, workspaceId, slackUserId, JSON.stringify(payload), now()).run();
  return true;
}

export async function memberForSlack(db: D1Database, slackUserId: string): Promise<Member | undefined> {
  const row = await first(db, "SELECT * FROM members WHERE slack_user_id = ?", slackUserId);
  return row ? memberFrom(row) : undefined;
}

export async function memberForEmail(db: D1Database, email: string): Promise<Member | undefined> {
  const row = await first(db, "SELECT * FROM members WHERE lower(email) = lower(?)", email);
  return row ? memberFrom(row) : undefined;
}

export async function createEngineeringBrief(db: D1Database, workspaceId: string, brief: EngineeringBrief): Promise<void> {
  const timestamp = now();
  await db.prepare(`INSERT INTO engineering_briefs (id, workspace_id, experiment_id, flag_key, variants_json, tracking_requirements_json, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(brief.id, workspaceId, brief.experimentId, brief.flagKey, JSON.stringify(brief.variants), JSON.stringify(brief.trackingRequirements), brief.status, timestamp, timestamp).run();
}

export async function createExecutionJob(db: D1Database, workspaceId: string, experimentId: string, fingerprint: string): Promise<{ id: string; created: boolean }> {
  const existing = await first(db, "SELECT id FROM execution_jobs WHERE experiment_id = ? AND kind = 'publish' AND approval_fingerprint = ?", experimentId, fingerprint);
  if (existing) return { id: String(existing.id), created: false };
  const job = { id: id("job"), created: true };
  await db.prepare(`INSERT INTO execution_jobs (id, workspace_id, experiment_id, kind, approval_fingerprint, status, created_at, updated_at)
    VALUES (?, ?, ?, 'publish', ?, 'queued', ?, ?)`)
    .bind(job.id, workspaceId, experimentId, fingerprint, now(), now()).run();
  return job;
}

export async function markJob(db: D1Database, jobId: string, status: "completed" | "failed", error?: string): Promise<void> {
  await db.prepare("UPDATE execution_jobs SET status = ?, error = ?, attempts = attempts + 1, updated_at = ? WHERE id = ?")
    .bind(status, error ?? null, now(), jobId).run();
}

export async function markExperimentLive(db: D1Database, experimentId: string, provider: string, externalId: string, externalUrl: string | undefined): Promise<void> {
  const existing = await getExperiment(db, experimentId);
  if (!existing) throw new Error("Experiment was not found.");
  await db.batch([
    db.prepare("UPDATE experiments SET status = 'live', updated_at = ? WHERE id = ?").bind(now(), experimentId),
    db.prepare(`INSERT INTO publications (id, workspace_id, experiment_id, provider, external_id, external_url, state, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 'live', ?, ?)
      ON CONFLICT(experiment_id, provider) DO UPDATE SET external_id = excluded.external_id, external_url = excluded.external_url, state = 'live', updated_at = excluded.updated_at`)
      .bind(id("publication"), existing.workspaceId, experimentId, provider, externalId, externalUrl ?? null, now(), now()),
    auditStatement(db, existing.workspaceId, undefined, "experiment_published", "experiment", experimentId, { provider, externalId })
  ]);
}

export async function audit(db: D1Database, workspaceId: string, actorId: string | undefined, kind: string, targetType: string, targetId: string, detail: unknown = {}): Promise<void> {
  await auditStatement(db, workspaceId, actorId, kind, targetType, targetId, detail).run();
}

export async function resetSandboxRecords(db: D1Database, workspaceId: string, actorId: string): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM publications WHERE workspace_id = ? AND provider = 'sandbox'").bind(workspaceId),
    db.prepare("DELETE FROM execution_jobs WHERE workspace_id = ? AND experiment_id IN (SELECT id FROM experiments WHERE workspace_id = ? AND channel = 'sandbox')").bind(workspaceId, workspaceId),
    db.prepare("DELETE FROM metric_snapshots WHERE workspace_id = ? AND (source_provider = 'sandbox' OR experiment_id IN (SELECT id FROM experiments WHERE workspace_id = ? AND channel = 'sandbox'))").bind(workspaceId, workspaceId),
    db.prepare("DELETE FROM learning_cards WHERE workspace_id = ? AND experiment_id IN (SELECT id FROM experiments WHERE workspace_id = ? AND channel = 'sandbox')").bind(workspaceId, workspaceId),
    db.prepare("DELETE FROM experiments WHERE workspace_id = ? AND channel = 'sandbox'").bind(workspaceId),
    auditStatement(db, workspaceId, actorId, "sandbox_records_reset", "workspace", workspaceId, { externalWrites: false })
  ]);
}

function auditStatement(db: D1Database, workspaceId: string, actorId: string | undefined, kind: string, targetType: string, targetId: string, detail: unknown): D1PreparedStatement {
  return db.prepare("INSERT INTO audit_events (id, workspace_id, actor_id, kind, target_type, target_id, detail_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
    .bind(id("audit"), workspaceId, actorId ?? null, kind, targetType, targetId, JSON.stringify(detail), now());
}
