import { demoDashboard } from "./demo";
import type {
  ApprovalSnapshot,
  AudienceDefinition,
  DashboardPayload,
  EngineeringBrief,
  Experiment,
  Goal,
  LearningCard,
  Member,
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
    detail: String(row.detail)
  };
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

  for (const goal of state.goals) {
    statements.push(
      db.prepare(`INSERT INTO goals (id, workspace_id, title, metric_kind, metric_name, baseline, target, unit, deadline, guardrail, monthly_budget_cents, status, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(goal.id, state.workspace.id, goal.title, goal.metricKind, goal.metricName, goal.baseline, goal.target, goal.unit, goal.deadline, goal.guardrail ?? null, goal.monthlyBudgetCents ?? null, goal.status, timestamp, timestamp)
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

export async function loadDashboard(db: D1Database): Promise<DashboardPayload> {
  await ensureDemoSeed(db);
  const workspaceRow = await first(db, "SELECT * FROM workspaces ORDER BY created_at LIMIT 1");
  if (!workspaceRow) throw new Error("Workspace seed failed.");
  const workspace = workspaceFrom(workspaceRow);
  const [memberRow, goalRows, experimentRows, cardRows, connectionRows, audienceRows, briefRows] = await Promise.all([
    first(db, "SELECT * FROM members WHERE workspace_id = ? ORDER BY CASE role WHEN 'admin' THEN 0 ELSE 1 END LIMIT 1", workspace.id),
    rows(db, "SELECT * FROM goals WHERE workspace_id = ? ORDER BY deadline", workspace.id),
    rows(db, "SELECT * FROM experiments WHERE workspace_id = ? ORDER BY updated_at DESC", workspace.id),
    rows(db, "SELECT * FROM learning_cards WHERE workspace_id = ? ORDER BY created_at DESC", workspace.id),
    rows(db, "SELECT * FROM provider_connections WHERE workspace_id = ? ORDER BY provider", workspace.id),
    rows(db, "SELECT * FROM audiences WHERE workspace_id = ? ORDER BY name", workspace.id),
    rows(db, "SELECT * FROM engineering_briefs WHERE workspace_id = ? ORDER BY created_at DESC", workspace.id)
  ]);
  if (!memberRow) throw new Error("No workspace member exists.");
  const monitor = await first(db, "SELECT created_at FROM audit_events WHERE workspace_id = ? AND kind = 'daily_monitor_completed' ORDER BY created_at DESC LIMIT 1", workspace.id);
  const plan = await first(db, "SELECT created_at FROM audit_events WHERE workspace_id = ? AND kind = 'weekly_plan_completed' ORDER BY created_at DESC LIMIT 1", workspace.id);
  return {
    workspace,
    me: memberFrom(memberRow),
    goals: goalRows.map(goalFrom),
    experiments: experimentRows.map(experimentFrom),
    learningCards: cardRows.map(cardFrom),
    connections: connectionRows.map(connectionFrom),
    audiences: audienceRows.map(audienceFrom),
    engineeringBriefs: briefRows.map(briefFrom),
    lastDailyMonitorAt: typeof monitor?.created_at === "string" ? monitor.created_at : undefined,
    lastWeeklyPlanAt: typeof plan?.created_at === "string" ? plan.created_at : undefined
  };
}

export async function createGoal(db: D1Database, workspaceId: string, input: Omit<Goal, "id" | "status">, actorId: string): Promise<Goal> {
  const goal: Goal = { id: id("goal"), ...input, status: "active" };
  const timestamp = now();
  await db.batch([
    db.prepare(`INSERT INTO goals (id, workspace_id, title, metric_kind, metric_name, baseline, target, unit, deadline, guardrail, monthly_budget_cents, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(goal.id, workspaceId, goal.title, goal.metricKind, goal.metricName, goal.baseline, goal.target, goal.unit, goal.deadline, goal.guardrail ?? null, goal.monthlyBudgetCents ?? null, goal.status, timestamp, timestamp),
    auditStatement(db, workspaceId, actorId, "goal_created", "goal", goal.id, { title: goal.title })
  ]);
  return goal;
}

export async function getExperiment(db: D1Database, experimentId: string): Promise<{ experiment: Experiment; workspaceId: string } | undefined> {
  const row = await first(db, "SELECT * FROM experiments WHERE id = ?", experimentId);
  return row ? { experiment: experimentFrom(row), workspaceId: String(row.workspace_id) } : undefined;
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

function auditStatement(db: D1Database, workspaceId: string, actorId: string | undefined, kind: string, targetType: string, targetId: string, detail: unknown): D1PreparedStatement {
  return db.prepare("INSERT INTO audit_events (id, workspace_id, actor_id, kind, target_type, target_id, detail_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
    .bind(id("audit"), workspaceId, actorId ?? null, kind, targetType, targetId, JSON.stringify(detail), now());
}
