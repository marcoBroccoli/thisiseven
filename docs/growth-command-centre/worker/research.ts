import type { EvidenceSnapshot, Goal } from "../shared/types";
import type { Env } from "./env";

export interface PublicResearchProvider {
  search(query: string): Promise<EvidenceSnapshot[]>;
}

type SearchResult = { title?: unknown; url?: unknown; snippet?: unknown };

/**
 * A provider-neutral public research seam. The endpoint is intentionally
 * configured by the workspace rather than hard-wiring a search vendor.
 */
export class ConfiguredSearchProvider implements PublicResearchProvider {
  constructor(private readonly env: Env) {}

  async search(query: string): Promise<EvidenceSnapshot[]> {
    if (!this.env.SEARCH_API_ENDPOINT) return [];
    const url = new URL(this.env.SEARCH_API_ENDPOINT);
    url.searchParams.set("q", query);
    const response = await fetch(url, {
      headers: this.env.SEARCH_API_TOKEN ? { authorization: `Bearer ${this.env.SEARCH_API_TOKEN}` } : undefined
    });
    if (!response.ok) throw new Error(`Public research request failed with HTTP ${response.status}.`);
    const body = await response.json<{ results?: SearchResult[] }>();
    return (body.results ?? []).flatMap((result, index) => {
      if (typeof result.title !== "string" || typeof result.url !== "string" || typeof result.snippet !== "string") return [];
      return [{
        id: `public_${index}_${crypto.randomUUID()}`,
        source: "public_web" as const,
        label: result.title.slice(0, 180),
        detail: result.snippet.slice(0, 500),
        url: result.url,
        capturedAt: new Date().toISOString()
      }];
    });
  }
}

export async function researchForGoal(env: Env, goal: Goal): Promise<EvidenceSnapshot[]> {
  const provider = new ConfiguredSearchProvider(env);
  const query = `${goal.metricName} growth experiments ${goal.title}`;
  try {
    return await provider.search(query);
  } catch (error) {
    console.warn("Public research unavailable; planning from workspace evidence only.", error);
    return [];
  }
}
