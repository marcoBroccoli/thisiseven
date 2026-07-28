import { z } from "zod";
import { channelIds } from "./types";

const MetricSourceProviderSchema = z.union([z.enum(channelIds), z.literal("posthog"), z.literal("workspace")]);

const SpendCapsSchema = z.object({
  dailyCents: z.number().int().positive().optional(),
  totalCents: z.number().int().positive().optional(),
  startAt: z.string().datetime().optional(),
  stopAt: z.string().datetime().optional()
});

const VariantSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1).max(120),
  headline: z.string().min(2).max(240),
  body: z.string().min(2).max(2_000),
  assetIds: z.array(z.string()),
  trackingUrl: z.string().url()
});

export const ExperimentProposalSchema = z.object({
  title: z.string().min(8).max(140),
  surface: z.enum(["email", "paid", "organic", "product"]),
  channel: z.union([z.enum(channelIds), z.literal("posthog")]),
  hypothesis: z.string().min(20).max(1_000),
  channelRationale: z.string().min(20).max(1_000),
  expectedImpact: z.enum(["low", "medium", "high"]),
  confidence: z.number().min(0).max(1),
  audienceId: z.string().optional(),
  optimizationMetric: z.string().min(2).max(120),
  successRule: z.string().min(10).max(500),
  decisionWindowDays: z.number().int().min(1).max(120),
  spend: SpendCapsSchema,
  engineeringFlagKey: z.string().regex(/^[a-z][a-z0-9_]*$/).optional()
});

export const GoalInputSchema = z.object({
  title: z.string().min(3).max(120),
  metricDefinitionId: z.string().min(1).optional(),
  metricKind: z.enum(["event", "funnel", "cohort", "custom"]),
  metricName: z.string().min(2).max(120),
  baseline: z.number().finite(),
  target: z.number().finite(),
  unit: z.string().min(1).max(24),
  deadline: z.string().date(),
  guardrail: z.string().max(240).optional(),
  monthlyBudgetCents: z.number().int().nonnegative().optional()
});

export const MetricDefinitionInputSchema = z.object({
  name: z.string().min(2).max(120),
  description: z.string().min(10).max(500),
  kind: z.enum(["event", "funnel", "cohort", "custom"]),
  sourceProvider: MetricSourceProviderSchema,
  calculation: z.string().min(5).max(1_000),
  sourceMetricId: z.string().min(1).max(120).optional(),
  unit: z.string().min(1).max(24),
  dimensions: z.array(z.string().min(1).max(80)).max(12),
  cadence: z.enum(["hourly", "daily", "weekly"])
});

export const PostHogConnectionConfigSchema = z.object({
  host: z.string().url().max(240),
  projectId: z.string().min(1).max(80),
  personalApiKey: z.string().min(8).max(1_000)
}).strict();

export const ExperimentDraftUpdateSchema = z.object({
  hypothesis: z.string().min(20).max(1_000),
  audienceId: z.string().min(1).optional(),
  successRule: z.string().min(10).max(500),
  decisionWindowDays: z.number().int().min(1).max(120),
  variants: z.array(VariantSchema).min(1).max(8),
  spend: SpendCapsSchema
});

export const ExperimentCreateSchema = z.object({
  goalId: z.string().min(1),
  title: z.string().min(8).max(140),
  surface: z.enum(["email", "paid", "organic", "product"]),
  channel: z.union([z.enum(channelIds), z.literal("posthog")]),
  hypothesis: z.string().min(20).max(1_000),
  channelRationale: z.string().min(20).max(1_000),
  expectedImpact: z.enum(["low", "medium", "high"]),
  confidence: z.number().min(0).max(1),
  audienceId: z.string().min(1).optional(),
  successRule: z.string().min(10).max(500),
  decisionWindowDays: z.number().int().min(1).max(120),
  variants: z.array(VariantSchema).min(1).max(8),
  spend: SpendCapsSchema,
  engineeringFlagKey: z.string().regex(/^[a-z][a-z0-9_]*$/).optional()
});
