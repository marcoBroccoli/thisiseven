import type { PostHogInsight } from "../shared/types";

export interface PostHogConnectionConfig {
  host: string;
  projectId: string;
  personalApiKey: string;
}

export interface AggregatePoint {
  value: number;
  capturedAt?: string;
  label?: string;
}

interface PostHogRequest {
  fetcher?: typeof fetch;
}

function normaliseHost(host: string): string {
  const url = new URL(host);
  return url.toString().replace(/\/$/, "");
}

function readableError(response: Response): Error {
  if (response.status === 401 || response.status === 403) return new Error("PostHog rejected the read-only API key or its insight:read permission.");
  if (response.status === 404) return new Error("PostHog could not find this project or saved insight.");
  if (response.status === 429) return new Error("PostHog rate limited this read. The monitor will retry on its next run.");
  return new Error(`PostHog read failed with HTTP ${response.status}.`);
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : undefined;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value : undefined;
}

function numericValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() && Number.isFinite(Number(value))) return Number(value);
  return undefined;
}

function dateValue(value: unknown): string | undefined {
  const string = stringValue(value);
  if (!string || Number.isNaN(Date.parse(string))) return undefined;
  return new Date(string).toISOString();
}

function pointFrom(value: unknown): AggregatePoint | undefined {
  const record = asRecord(value);
  if (!record) return undefined;
  const numericKeys = ["value", "count", "aggregated_value", "total", "y"];
  const valueNumber = numericKeys.map((key) => numericValue(record[key])).find((item): item is number => item !== undefined);
  if (valueNumber === undefined) return undefined;
  return {
    value: valueNumber,
    capturedAt: ["date", "day", "timestamp", "time"].map((key) => dateValue(record[key])).find(Boolean),
    label: ["label", "date", "day", "name"].map((key) => stringValue(record[key])).find(Boolean)
  };
}

/**
 * Saved insight responses differ by insight type. This deliberately accepts only
 * aggregate numbers from known result containers and does not traverse person,
 * event, or property payloads.
 */
export function aggregatePointsFromInsight(payload: unknown): AggregatePoint[] {
  const root = asRecord(payload);
  if (!root) return [];
  const containers = [root.result, root.results, root.data, root.series].flatMap((value) => Array.isArray(value) ? value : []);
  const direct = pointFrom(root);
  const points = containers.flatMap((container) => {
    if (Array.isArray(container)) return container.map(pointFrom).filter((point): point is AggregatePoint => Boolean(point));
    const record = asRecord(container);
    if (!record) return [];
    const nested = [record.data, record.results, record.series].flatMap((value) => Array.isArray(value) ? value : []);
    return [pointFrom(record), ...nested.map(pointFrom)].filter((point): point is AggregatePoint => Boolean(point));
  });
  return direct ? [direct, ...points] : points;
}

export class PostHogAnalyticsProvider {
  private readonly host: string;
  private readonly fetcher: typeof fetch;

  constructor(private readonly config: PostHogConnectionConfig, request: PostHogRequest = {}) {
    this.host = normaliseHost(config.host);
    this.fetcher = request.fetcher ?? fetch;
  }

  private async read(path: string): Promise<unknown> {
    const response = await this.fetcher(`${this.host}/api/projects/${encodeURIComponent(this.config.projectId)}${path}`, {
      headers: {
        authorization: `Bearer ${this.config.personalApiKey}`,
        accept: "application/json"
      }
    });
    if (!response.ok) throw readableError(response);
    return response.json();
  }

  async listInsights(): Promise<PostHogInsight[]> {
    const payload = await this.read("/insights/?limit=100");
    const root = asRecord(payload);
    const records = Array.isArray(payload) ? payload : Array.isArray(root?.results) ? root.results : [];
    return records.flatMap((item) => {
      const record = asRecord(item);
      if (!record) return [];
      const id = stringValue(record.id) ?? numericValue(record.id)?.toString();
      const name = stringValue(record.name);
      if (!id || !name) return [];
      return [{ id, name, description: stringValue(record.description), kind: stringValue(record.derived_name) ?? stringValue(record.insight) }];
    });
  }

  async latestAggregate(insightId: string): Promise<AggregatePoint | undefined> {
    const payload = await this.read(`/insights/${encodeURIComponent(insightId)}/`);
    const points = aggregatePointsFromInsight(payload);
    return points.sort((left, right) => (left.capturedAt ?? "").localeCompare(right.capturedAt ?? ""))[points.length - 1];
  }
}
