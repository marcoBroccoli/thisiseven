import type { ApprovalSnapshot, Experiment, ExperimentStatus, ProviderCapability, Role, SpendCaps } from "./types";

const restrictedModelKeys = /(^|_)(email|phone|name|address|person|contact|ip)($|_)/i;

export function canManageConnections(role: Role): boolean {
  return role === "admin";
}

export function canApproveExternalAction(role: Role): boolean {
  return role === "admin";
}

export function approvalIssues(
  experiment: Experiment,
  capabilities: readonly ProviderCapability[],
  audienceEligible = true,
  flagRegistered = true
): string[] {
  const issues: string[] = [];
  const isPaid = experiment.surface === "paid";
  const requiredCapability = isPaid
    ? "create_campaign"
    : experiment.surface === "organic"
      ? "publish_organic"
      : experiment.surface === "email"
        ? "send_email"
        : "create_product_experiment";

  if (!capabilities.includes(requiredCapability)) issues.push("The selected channel is not authorized for this action.");
  if (!experiment.optimizationMetric.trim()) issues.push("Choose an optimization metric.");
  if (!experiment.successRule.trim()) issues.push("Define a success rule.");
  if (!experiment.variants.length) issues.push("Add at least one creative variant.");
  if (experiment.surface === "email" && !audienceEligible) issues.push("The audience is not consented for email delivery.");
  if (experiment.surface === "product" && !flagRegistered) issues.push("The product flag has not been registered by engineering.");
  if (isPaid) issues.push(...spendIssues(experiment.spend));
  return issues;
}

export function spendIssues(spend: SpendCaps): string[] {
  const issues: string[] = [];
  if (!spend.dailyCents) issues.push("Set a daily spend cap.");
  if (!spend.totalCents) issues.push("Set a total spend cap.");
  if (!spend.startAt) issues.push("Set a campaign start date.");
  if (!spend.stopAt) issues.push("Set a campaign stop date.");
  if (spend.dailyCents && spend.totalCents && spend.dailyCents > spend.totalCents) {
    issues.push("The daily cap cannot exceed the total cap.");
  }
  if (spend.startAt && spend.stopAt && new Date(spend.stopAt) <= new Date(spend.startAt)) {
    issues.push("The campaign stop date must be after its start date.");
  }
  return issues;
}

export function approvalFingerprint(experiment: Experiment): string {
  const value = JSON.stringify({
    id: experiment.id,
    channel: experiment.channel,
    audienceId: experiment.audienceId,
    metric: experiment.optimizationMetric,
    success: experiment.successRule,
    variants: experiment.variants.map((variant) => ({ id: variant.id, body: variant.body, assets: variant.assetIds })),
    spend: experiment.spend,
    flag: experiment.engineeringFlagKey
  });
  let hash = 5381;
  for (const character of value) hash = (hash * 33) ^ character.charCodeAt(0);
  return `approval_${(hash >>> 0).toString(36)}`;
}

export function createApprovalSnapshot(experiment: Experiment, actorId: string, audienceName?: string): ApprovalSnapshot {
  return {
    experimentId: experiment.id,
    capturedAt: new Date().toISOString(),
    capturedBy: actorId,
    channel: experiment.channel,
    audienceName,
    optimizationMetric: experiment.optimizationMetric,
    spend: experiment.spend,
    variantIds: experiment.variants.map((variant) => variant.id),
    fingerprint: approvalFingerprint(experiment)
  };
}

export function nextApprovalStatus(experiment: Experiment, issues: string[]): ExperimentStatus {
  if (experiment.surface === "product" && experiment.engineeringBrief && issues.some((issue) => issue.includes("registered"))) {
    return "awaiting_engineering";
  }
  return issues.length ? "blocked" : "awaiting_approval";
}

export function buildTrackingUrl(destination: string, experiment: Experiment): string {
  const url = new URL(destination);
  url.searchParams.set("utm_source", experiment.channel.replace("_", "-"));
  url.searchParams.set("utm_medium", experiment.surface);
  url.searchParams.set("utm_campaign", `exp-${experiment.id}`);
  return url.toString();
}

export function redactForModel(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redactForModel);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).flatMap(([key, nested]) =>
      restrictedModelKeys.test(key) ? [] : [[key, redactForModel(nested)]]
    )
  );
}

export function hasRestrictedModelData(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(hasRestrictedModelData);
  if (!value || typeof value !== "object") return false;
  return Object.entries(value as Record<string, unknown>).some(
    ([key, nested]) => restrictedModelKeys.test(key) || hasRestrictedModelData(nested)
  );
}
