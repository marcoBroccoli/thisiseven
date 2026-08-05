import type { Experiment, Goal, LearningCard, MetricSnapshot } from "./types";

export interface SandboxRun {
  experiment: Experiment;
  learningCard: LearningCard;
  metricSnapshot: MetricSnapshot;
}

/** Creates a complete local-only learning loop. It never resolves an audience or provider. */
export function createSandboxRun(goal: Goal, at = new Date()): SandboxRun {
  const timestamp = at.toISOString();
  const experimentId = `exp_sandbox_${crypto.randomUUID()}`;
  const simulatedLift = Math.max(1, Math.min(5, Math.round((goal.target - goal.baseline) / 4)));
  const simulatedResult = goal.baseline + simulatedLift;
  const experiment: Experiment = {
    id: experimentId,
    goalId: goal.id,
    title: `Sandbox test: clarify the first ${goal.metricName} step`,
    surface: "email",
    channel: "sandbox",
    status: "completed",
    hypothesis: "A clearer first-step message will improve the selected activation metric in a safe simulated run.",
    channelRationale: "Sandbox is built in for testing the experiment workflow without an audience, account, spend, or external provider.",
    expectedImpact: "low",
    confidence: 0.95,
    optimizationMetric: goal.metricName,
    successRule: `Simulate an improvement from ${goal.baseline}${goal.unit} while preserving ${goal.guardrail ?? "the configured guardrail"}.`,
    decisionWindowDays: 7,
    variants: [{
      id: `variant_sandbox_${crypto.randomUUID()}`,
      name: "Guided first step",
      headline: "Start your first shared project",
      body: "This simulated message demonstrates the approval, publication, and learning flow without a delivery provider.",
      assetIds: [],
      trackingUrl: "https://sandbox.invalid/experiment"
    }],
    spend: {},
    createdAt: timestamp,
    updatedAt: timestamp
  };

  return {
    experiment,
    metricSnapshot: {
      id: `snapshot_sandbox_${crypto.randomUUID()}`,
      metricDefinitionId: goal.metricDefinitionId,
      experimentId,
      sourceProvider: "sandbox",
      value: simulatedResult,
      dimensions: { environment: "sandbox", workflow: "test_experiment" },
      trustLevel: "simulated",
      quality: "verified",
      capturedAt: timestamp
    },
    learningCard: {
      id: `card_sandbox_${crypto.randomUUID()}`,
      experimentId,
      evidence: [{
        id: `evidence_sandbox_${crypto.randomUUID()}`,
        source: "workspace",
        label: "Sandbox metric snapshot",
        detail: `Simulated ${goal.metricName} moved from ${goal.baseline}${goal.unit} to ${simulatedResult}${goal.unit}. No customer, provider, or paid-channel data was used.`,
        capturedAt: timestamp
      }],
      expectedImpact: "low",
      confidence: 0.95,
      outcome: "win",
      outcomeSummary: `Sandbox completed with a simulated ${simulatedLift}${goal.unit} lift. This is a workflow check, not a production result.`,
      nextAction: "Review the learning card, then connect a real provider only when ready.",
      evaluatedAt: timestamp
    }
  };
}
