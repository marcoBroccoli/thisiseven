export const channelIds = [
  "sandbox",
  "resend",
  "linkedin",
  "meta",
  "tiktok",
  "snapchat",
  "google_ads",
  "x",
  "reddit",
  "pinterest"
] as const;

export type ChannelId = (typeof channelIds)[number];
export type ExperimentChannel = ChannelId | "posthog";
export type Role = "admin" | "operator" | "viewer";
export type GoalMetricKind = "event" | "funnel" | "cohort" | "custom";
export type ExperimentSurface = "email" | "paid" | "organic" | "product";
export type ExperimentStatus =
  | "proposed"
  | "needs_changes"
  | "awaiting_engineering"
  | "awaiting_approval"
  | "approved"
  | "queued"
  | "live"
  | "measuring"
  | "completed"
  | "failed"
  | "cancelled"
  | "blocked";
export type Outcome = "win" | "loss" | "inconclusive" | "stopped" | "pending";
export type ConnectionStatus = "not_connected" | "pending_access" | "connected" | "revoked";
export type DataTrustLevel = "observed" | "modeled" | "simulated" | "unavailable";
export type DataQuality = "verified" | "provisional" | "degraded" | "not_ready";
export type SourceFreshness = "fresh" | "stale" | "not_synced";
export type MetricDefinitionStatus = "draft" | "ready" | "needs_connection" | "archived";
export type MetricSourceProvider = ChannelId | "posthog" | "workspace";

export interface Workspace {
  id: string;
  name: string;
  productName: string;
  timezone: string;
}

export interface Member {
  id: string;
  name: string;
  email: string;
  role: Role;
  slackUserId?: string;
}

export interface Goal {
  id: string;
  title: string;
  metricDefinitionId?: string;
  metricKind: GoalMetricKind;
  metricName: string;
  baseline: number;
  target: number;
  unit: string;
  deadline: string;
  guardrail?: string;
  monthlyBudgetCents?: number;
  status: "active" | "paused" | "completed";
}

export interface MetricDefinition {
  id: string;
  name: string;
  description: string;
  kind: GoalMetricKind;
  sourceProvider: MetricSourceProvider;
  calculation: string;
  /** The read-only source record, for example a saved PostHog insight ID. */
  sourceMetricId?: string;
  unit: string;
  dimensions: string[];
  cadence: "hourly" | "daily" | "weekly";
  trustLevel: DataTrustLevel;
  status: MetricDefinitionStatus;
  ownerMemberId?: string;
  version: number;
  lastSyncedAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface MetricDefinitionInput {
  name: string;
  description: string;
  kind: GoalMetricKind;
  sourceProvider: MetricSourceProvider;
  calculation: string;
  sourceMetricId?: string;
  unit: string;
  dimensions: string[];
  cadence: MetricDefinition["cadence"];
}

export interface MetricSnapshot {
  id: string;
  metricDefinitionId?: string;
  experimentId?: string;
  sourceProvider: MetricSourceProvider;
  value: number;
  dimensions: Record<string, string | number | boolean>;
  trustLevel: DataTrustLevel;
  quality: DataQuality;
  capturedAt: string;
}

export interface DataSource {
  id: string;
  provider: MetricSourceProvider;
  label: string;
  status: ConnectionStatus;
  trustLevel: DataTrustLevel;
  freshness: SourceFreshness;
  lastSyncedAt?: string;
  syncError?: string;
  cadence: MetricDefinition["cadence"];
  scope: string;
  detail: string;
}

export interface AudienceDefinition {
  id: string;
  name: string;
  posthogCohortId?: string;
  estimatedPeople: number;
  consentProperty: string;
  emailProperty: string;
  eligible: boolean;
}

export interface Variant {
  id: string;
  name: string;
  headline: string;
  body: string;
  assetIds: string[];
  trackingUrl: string;
}

export interface SpendCaps {
  dailyCents?: number;
  totalCents?: number;
  startAt?: string;
  stopAt?: string;
}

export interface Experiment {
  id: string;
  goalId: string;
  title: string;
  surface: ExperimentSurface;
  channel: ExperimentChannel;
  status: ExperimentStatus;
  hypothesis: string;
  channelRationale: string;
  expectedImpact: "low" | "medium" | "high";
  confidence: number;
  audienceId?: string;
  optimizationMetric: string;
  successRule: string;
  decisionWindowDays: number;
  variants: Variant[];
  spend: SpendCaps;
  engineeringFlagKey?: string;
  engineeringBrief?: string;
  approvalSnapshot?: ApprovalSnapshot;
  createdAt: string;
  updatedAt: string;
}

export interface ExperimentDraftUpdate {
  hypothesis: string;
  audienceId?: string;
  successRule: string;
  decisionWindowDays: number;
  variants: Variant[];
  spend: SpendCaps;
}

export interface ExperimentCreateInput {
  goalId: string;
  title: string;
  surface: ExperimentSurface;
  channel: ExperimentChannel;
  hypothesis: string;
  channelRationale: string;
  expectedImpact: Experiment["expectedImpact"];
  confidence: number;
  audienceId?: string;
  successRule: string;
  decisionWindowDays: number;
  variants: Variant[];
  spend: SpendCaps;
  engineeringFlagKey?: string;
}

export interface ApprovalSnapshot {
  experimentId: string;
  capturedAt: string;
  capturedBy: string;
  channel: ExperimentChannel;
  audienceName?: string;
  optimizationMetric: string;
  spend: SpendCaps;
  variantIds: string[];
  fingerprint: string;
}

export interface LearningCard {
  id: string;
  experimentId: string;
  evidence: EvidenceSnapshot[];
  expectedImpact: "low" | "medium" | "high";
  confidence: number;
  outcome: Outcome;
  outcomeSummary: string;
  nextAction: string;
  evaluatedAt?: string;
}

export interface EvidenceSnapshot {
  id: string;
  source: "posthog" | "channel" | "public_web" | "workspace";
  label: string;
  detail: string;
  url?: string;
  capturedAt: string;
}

export interface ProviderConnection {
  id: string;
  provider: ChannelId | "posthog" | "slack" | "media";
  label: string;
  status: ConnectionStatus;
  capabilities: ProviderCapability[];
  lastSyncedAt?: string;
  syncError?: string;
  detail: string;
}

export interface PostHogInsight {
  id: string;
  name: string;
  description?: string;
  kind?: string;
}

export type ProviderCapability =
  | "read_analytics"
  | "resolve_audience"
  | "send_email"
  | "publish_organic"
  | "create_campaign"
  | "read_channel_metrics"
  | "create_product_experiment"
  | "generate_image"
  | "generate_video";

export interface EngineeringBrief {
  id: string;
  experimentId: string;
  flagKey: string;
  variants: string[];
  trackingRequirements: string[];
  status: "waiting_for_engineering" | "registered";
}

export interface DashboardPayload {
  workspace: Workspace;
  me: Member;
  goals: Goal[];
  experiments: Experiment[];
  learningCards: LearningCard[];
  connections: ProviderConnection[];
  dataSources: DataSource[];
  metricDefinitions: MetricDefinition[];
  metricSnapshots: MetricSnapshot[];
  audiences: AudienceDefinition[];
  engineeringBriefs: EngineeringBrief[];
  lastDailyMonitorAt?: string;
  lastWeeklyPlanAt?: string;
  sandboxMode: boolean;
}

export interface SlackDecision {
  experimentId: string;
  action: "approve" | "reject" | "pause";
  actorSlackUserId: string;
  actionId: string;
}

export interface ExecutionJob {
  id: string;
  experimentId: string;
  approvalFingerprint: string;
  kind: "publish" | "pause" | "daily_monitor" | "weekly_plan";
}
