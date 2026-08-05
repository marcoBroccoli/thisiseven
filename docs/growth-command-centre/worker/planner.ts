import type { DashboardPayload, Experiment, Goal, LearningCard } from "../shared/types";
import { buildTrackingUrl } from "../shared/safety";
import { AnthropicModelProvider, modelContext, type ModelProposal } from "./model";
import type { Env } from "./env";
import { researchForGoal } from "./research";

const timestamp = () => new Date().toISOString();

function fallbackProposal(goal: Goal, dashboard: DashboardPayload): ModelProposal {
  const audience = dashboard.audiences.find((item) => item.eligible);
  const resend = dashboard.connections.find((item) => item.provider === "resend" && item.status === "connected");
  if (resend && audience) {
    return {
      title: `Help high-intent trials reach ${goal.metricName}`,
      surface: "email",
      channel: "resend",
      hypothesis: "A concise lifecycle prompt focused on the activation gap will move eligible high-intent trials to the target action.",
      channelRationale: "Resend is connected, the cohort is consented, and email is lower cost than paid acquisition for this existing intent.",
      expectedImpact: "medium",
      confidence: 0.66,
      audienceId: audience.id,
      optimizationMetric: goal.metricName,
      successRule: `Increase ${goal.metricName} by at least 10% over the ${goal.baseline}${goal.unit} baseline without violating ${goal.guardrail ?? "the configured guardrail"}.`,
      decisionWindowDays: 14,
      spend: {}
    };
  }
  return {
    title: `Investigate the largest ${goal.metricName} drop-off`,
    surface: "product",
    channel: "posthog",
    hypothesis: "A product intervention at the largest observed drop-off will improve the selected goal metric.",
    channelRationale: "No connected distribution channel can safely execute yet, so the next action should become an engineering-ready product test.",
    expectedImpact: "medium",
    confidence: 0.5,
    optimizationMetric: goal.metricName,
    successRule: `Improve ${goal.metricName} from ${goal.baseline}${goal.unit} toward ${goal.target}${goal.unit} without violating the guardrail.`,
    decisionWindowDays: 21,
    spend: {},
    engineeringFlagKey: `improve_${goal.id.replace(/^goal_/, "")}`
  };
}

export async function weeklyProposal(env: Env, dashboard: DashboardPayload, goal: Goal): Promise<{ experiment: Experiment; learningCard: LearningCard }> {
  const provider = new AnthropicModelProvider(env);
  const research = await researchForGoal(env, goal);
  let proposal: ModelProposal | undefined;
  try {
    proposal = await provider.proposeExperiment(modelContext(dashboard, goal, research.flatMap((item) => item.url ? [{ label: item.label, detail: item.detail, url: item.url }] : [])));
  } catch (error) {
    console.error("AI proposal failed; using deterministic fallback.", error);
  }
  proposal ??= fallbackProposal(goal, dashboard);
  const experiment: Experiment = {
    id: `exp_${crypto.randomUUID()}`,
    goalId: goal.id,
    title: proposal.title,
    surface: proposal.surface,
    channel: proposal.channel,
    status: proposal.surface === "product" ? "awaiting_engineering" : "proposed",
    hypothesis: proposal.hypothesis,
    channelRationale: proposal.channelRationale,
    expectedImpact: proposal.expectedImpact,
    confidence: proposal.confidence,
    audienceId: proposal.audienceId,
    optimizationMetric: proposal.optimizationMetric,
    successRule: proposal.successRule,
    decisionWindowDays: proposal.decisionWindowDays,
    variants: [
      {
        id: `variant_${crypto.randomUUID()}`,
        name: "AI proposal",
        headline: proposal.title,
        body: proposal.hypothesis,
        assetIds: [],
        trackingUrl: "https://example.invalid"
      }
    ],
    spend: proposal.spend,
    engineeringFlagKey: proposal.engineeringFlagKey,
    engineeringBrief: proposal.engineeringFlagKey
      ? `Implement the ${proposal.engineeringFlagKey} flag with control and treatment variants. Capture the selected metric and the guardrail before registration.`
      : undefined,
    createdAt: timestamp(),
    updatedAt: timestamp()
  };
  experiment.variants[0].trackingUrl = buildTrackingUrl("https://product.example.com", experiment);
  const card: LearningCard = {
    id: `card_${crypto.randomUUID()}`,
    experimentId: experiment.id,
    evidence: [
      {
        id: `evidence_${crypto.randomUUID()}`,
        source: "workspace",
        label: "Weekly plan",
        detail: `AI selected ${experiment.channel} for ${goal.title} using the configured metric, available channel capabilities, and aggregate audience eligibility.`,
        capturedAt: timestamp()
      },
      ...research
    ],
    expectedImpact: experiment.expectedImpact,
    confidence: experiment.confidence,
    outcome: "pending",
    outcomeSummary: "Proposal is waiting for engineering registration or administrator approval.",
    nextAction: experiment.surface === "product" ? "Register the product flag and tracking contract." : "Review the proposed approval package in Slack."
  };
  return { experiment, learningCard: card };
}
