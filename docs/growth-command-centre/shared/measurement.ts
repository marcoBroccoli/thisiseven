import type { DataQuality, DataTrustLevel, MetricDefinition, MetricSnapshot, SourceFreshness } from "./types";

export const trustLabels: Record<DataTrustLevel, string> = {
  observed: "Observed",
  modeled: "Modeled",
  simulated: "Simulated",
  unavailable: "Unavailable"
};

export const qualityLabels: Record<DataQuality, string> = {
  verified: "Verified",
  provisional: "Provisional",
  degraded: "Degraded",
  not_ready: "Not ready"
};

export const freshnessLabels: Record<SourceFreshness, string> = {
  fresh: "Fresh",
  stale: "Stale",
  not_synced: "Not synced"
};

export function latestSnapshot(snapshots: MetricSnapshot[], metricDefinitionId?: string): MetricSnapshot | undefined {
  return snapshots
    .filter((snapshot) => !metricDefinitionId || snapshot.metricDefinitionId === metricDefinitionId)
    .sort((left, right) => right.capturedAt.localeCompare(left.capturedAt))[0];
}

export function metricIsLive(definition: MetricDefinition | undefined, snapshot: MetricSnapshot | undefined): boolean {
  return definition?.status === "ready" && definition.trustLevel === "observed" && snapshot?.trustLevel === "observed" && snapshot.quality === "verified";
}

export function sourceFreshness(lastSyncedAt: string | undefined, cadence: MetricDefinition["cadence"], at = new Date()): SourceFreshness {
  if (!lastSyncedAt) return "not_synced";
  const windowMs = cadence === "hourly" ? 2 * 60 * 60 * 1000 : cadence === "daily" ? 36 * 60 * 60 * 1000 : 9 * 24 * 60 * 60 * 1000;
  return at.getTime() - new Date(lastSyncedAt).getTime() <= windowMs ? "fresh" : "stale";
}
