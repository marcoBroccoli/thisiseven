import { ExperimentProposalSchema } from "../shared/contracts";
import { redactForModel } from "../shared/safety";
import type { AudienceDefinition, DashboardPayload, Experiment, Goal } from "../shared/types";
import type { Env } from "./env";

export interface ModelProvider {
  proposeExperiment(context: ModelContext): Promise<ModelProposal | undefined>;
}

export interface ModelContext {
  goal: Goal;
  audiences: Pick<AudienceDefinition, "id" | "name" | "estimatedPeople" | "eligible" | "consentProperty">[];
  connectedChannels: string[];
  recentLearning: { title: string; outcome: string; nextAction: string }[];
  publicResearch?: { label: string; detail: string; url: string }[];
}

export interface ModelProposal {
  title: string;
  surface: Experiment["surface"];
  channel: Experiment["channel"];
  hypothesis: string;
  channelRationale: string;
  expectedImpact: Experiment["expectedImpact"];
  confidence: number;
  audienceId?: string;
  optimizationMetric: string;
  successRule: string;
  decisionWindowDays: number;
  spend: Experiment["spend"];
  engineeringFlagKey?: string;
}

export class AnthropicModelProvider implements ModelProvider {
  constructor(private readonly env: Env) {}

  async proposeExperiment(context: ModelContext): Promise<ModelProposal | undefined> {
    if (!this.env.ANTHROPIC_API_KEY) return undefined;
    const safeContext = redactForModel(context);
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": this.env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01"
      },
      body: JSON.stringify({
        model: this.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5",
        max_tokens: 1200,
        system: "You are a careful growth strategist. Use only aggregate facts. Propose one approval-gated experiment as JSON, never include customer identifiers, and choose only a connected channel.",
        messages: [{ role: "user", content: JSON.stringify(safeContext) }]
      })
    });
    if (!response.ok) throw new Error(`Claude planning request failed with HTTP ${response.status}.`);
    const payload = await response.json<{ content?: { type: string; text?: string }[] }>();
    const text = payload.content?.find((part) => part.type === "text")?.text;
    if (!text) return undefined;
    const candidate = JSON.parse(text) as unknown;
    const parsed = ExperimentProposalSchema.safeParse(candidate);
    return parsed.success ? parsed.data : undefined;
  }
}

export function modelContext(dashboard: DashboardPayload, goal: Goal, publicResearch: ModelContext["publicResearch"] = []): ModelContext {
  return {
    goal,
    audiences: dashboard.audiences.map(({ id, name, estimatedPeople, eligible, consentProperty }) => ({ id, name, estimatedPeople, eligible, consentProperty })),
    connectedChannels: dashboard.connections.filter((connection) => connection.status === "connected").map((connection) => connection.provider),
    recentLearning: dashboard.learningCards.map((card) => {
      const experiment = dashboard.experiments.find((item) => item.id === card.experimentId);
      return { title: experiment?.title ?? "Previous experiment", outcome: card.outcome, nextAction: card.nextAction };
    }),
    publicResearch
  };
}
