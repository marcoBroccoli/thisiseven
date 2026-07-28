import type { DashboardPayload, Experiment, ExperimentCreateInput, ExperimentDraftUpdate, Goal, MetricDefinition, MetricDefinitionInput, MetricSnapshot, PostHogInsight, ProviderConnection } from "../shared/types";

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...options,
    headers: { "content-type": "application/json", ...(options?.headers ?? {}) }
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({})) as { error?: string };
    throw new Error(body.error ?? `Request failed with HTTP ${response.status}.`);
  }
  return response.json() as Promise<T>;
}

export const api = {
  dashboard: () => request<DashboardPayload>("/api/dashboard"),
  createGoal: (goal: Omit<Goal, "id" | "status">) => request<Goal>("/api/goals", { method: "POST", body: JSON.stringify(goal) }),
  createMetric: (metric: MetricDefinitionInput) => request<MetricDefinition>("/api/metrics", { method: "POST", body: JSON.stringify(metric) }),
  metricSnapshots: (metricId: string, limit = 90) => request<{ metric: MetricDefinition; snapshots: MetricSnapshot[] }>(`/api/metrics/${metricId}/snapshots?limit=${limit}`),
  createExperiment: (experiment: ExperimentCreateInput) => request<Experiment>("/api/experiments", { method: "POST", body: JSON.stringify(experiment) }),
  runSandbox: () => request("/api/sandbox/run", { method: "POST" }),
  resetSandbox: () => request("/api/sandbox/reset", { method: "POST" }),
  updateExperiment: (experimentId: string, update: ExperimentDraftUpdate) => request<Experiment>(`/api/experiments/${experimentId}`, { method: "PUT", body: JSON.stringify(update) }),
  approve: (experimentId: string) => request(`/api/experiments/${experimentId}/approve`, { method: "POST" }),
  reject: (experimentId: string) => request(`/api/experiments/${experimentId}/reject`, { method: "POST" }),
  monitor: () => request("/api/automation/daily-monitor", { method: "POST" }),
  weeklyPlan: () => request("/api/automation/weekly-plan", { method: "POST" }),
  configureConnection: (provider: ProviderConnection["provider"], config: unknown) => request<{ ok: boolean }>(`/api/connections/${provider}/config`, { method: "PUT", body: JSON.stringify(config) }),
  verifyPostHog: () => request<{ ok: boolean; insights: PostHogInsight[] }>("/api/connections/posthog/verify", { method: "POST" }),
  posthogInsights: () => request<{ insights: PostHogInsight[] }>("/api/connections/posthog/insights")
};
