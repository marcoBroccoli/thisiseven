import { z } from "zod";
import { channelIds } from "./types";

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
  spend: z.object({
    dailyCents: z.number().int().positive().optional(),
    totalCents: z.number().int().positive().optional(),
    startAt: z.string().datetime().optional(),
    stopAt: z.string().datetime().optional()
  }),
  engineeringFlagKey: z.string().regex(/^[a-z][a-z0-9_]*$/).optional()
});

export const GoalInputSchema = z.object({
  title: z.string().min(3).max(120),
  metricKind: z.enum(["event", "funnel", "cohort", "custom"]),
  metricName: z.string().min(2).max(120),
  baseline: z.number().finite(),
  target: z.number().finite(),
  unit: z.string().min(1).max(24),
  deadline: z.string().date(),
  guardrail: z.string().max(240).optional(),
  monthlyBudgetCents: z.number().int().nonnegative().optional()
});
