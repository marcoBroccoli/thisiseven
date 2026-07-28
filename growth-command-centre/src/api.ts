import type { DashboardPayload, Goal } from "../shared/types";

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
  approve: (experimentId: string) => request(`/api/experiments/${experimentId}/approve`, { method: "POST" }),
  reject: (experimentId: string) => request(`/api/experiments/${experimentId}/reject`, { method: "POST" }),
  monitor: () => request("/api/automation/daily-monitor", { method: "POST" }),
  weeklyPlan: () => request("/api/automation/weekly-plan", { method: "POST" })
};
