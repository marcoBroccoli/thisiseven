import { describe, expect, it } from "vitest";
import { latestSnapshot, metricIsLive, sourceFreshness } from "../shared/measurement";
import type { MetricDefinition, MetricSnapshot } from "../shared/types";

const definition: MetricDefinition = {
  id: "metric_activation",
  name: "Activation",
  description: "Activation rate",
  kind: "funnel",
  sourceProvider: "posthog",
  calculation: "Activated / signup",
  unit: "%",
  dimensions: [],
  cadence: "daily",
  trustLevel: "observed",
  status: "ready",
  version: 1,
  createdAt: "2026-07-01T00:00:00.000Z",
  updatedAt: "2026-07-01T00:00:00.000Z"
};

const observedSnapshot: MetricSnapshot = {
  id: "snapshot_observed",
  metricDefinitionId: definition.id,
  sourceProvider: "posthog",
  value: 34,
  dimensions: {},
  trustLevel: "observed",
  quality: "verified",
  capturedAt: "2026-07-28T08:00:00.000Z"
};

describe("measurement contract", () => {
  it("returns the most recent snapshot for a metric", () => {
    const oldest = { ...observedSnapshot, id: "snapshot_old", value: 31, capturedAt: "2026-07-27T08:00:00.000Z" };
    expect(latestSnapshot([oldest, observedSnapshot], definition.id)?.id).toBe(observedSnapshot.id);
  });

  it("only treats verified observed data as live", () => {
    expect(metricIsLive(definition, observedSnapshot)).toBe(true);
    expect(metricIsLive(definition, { ...observedSnapshot, trustLevel: "simulated" })).toBe(false);
    expect(metricIsLive({ ...definition, status: "needs_connection" }, observedSnapshot)).toBe(false);
  });

  it("marks a daily source stale after its freshness window", () => {
    expect(sourceFreshness("2026-07-28T08:00:00.000Z", "daily", new Date("2026-07-29T18:00:00.000Z"))).toBe("fresh");
    expect(sourceFreshness("2026-07-28T08:00:00.000Z", "daily", new Date("2026-07-30T00:00:00.000Z"))).toBe("stale");
    expect(sourceFreshness(undefined, "daily", new Date("2026-07-30T00:00:00.000Z"))).toBe("not_synced");
  });
});
