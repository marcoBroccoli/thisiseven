export const channelIds = [
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
  detail: string;
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
  audiences: AudienceDefinition[];
  engineeringBriefs: EngineeringBrief[];
  lastDailyMonitorAt?: string;
  lastWeeklyPlanAt?: string;
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
