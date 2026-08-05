import { describe, expect, it } from "vitest";
import { approvalIssues, buildTrackingUrl, hasRestrictedModelData, redactForModel } from "../shared/safety";
import type { Experiment } from "../shared/types";

const paidExperiment: Experiment = {
  id: "exp_paid",
  goalId: "goal_activation",
  title: "Test founder story ad",
  surface: "paid",
  channel: "linkedin",
  status: "proposed",
  hypothesis: "A founder story will increase qualified signup conversion for product-led teams.",
  channelRationale: "LinkedIn reaches the existing B2B audience with sufficient targeting context.",
  expectedImpact: "medium",
  confidence: 0.68,
  optimizationMetric: "Activated accounts",
  successRule: "Increase activated accounts by 12% versus the rolling baseline.",
  decisionWindowDays: 14,
  variants: [{ id: "v1", name: "Founder story", headline: "Stop guessing", body: "A better way.", assetIds: [], trackingUrl: "https://example.com" }],
  spend: {},
  createdAt: "2026-07-28T00:00:00.000Z",
  updatedAt: "2026-07-28T00:00:00.000Z"
};

describe("approval safety", () => {
  it("blocks a paid experiment until all spend controls are set", () => {
    expect(approvalIssues(paidExperiment, ["create_campaign"])).toEqual([
      "Set a daily spend cap.",
      "Set a total spend cap.",
      "Set a campaign start date.",
      "Set a campaign stop date."
    ]);
  });

  it("adds immutable UTM attribution", () => {
    expect(buildTrackingUrl("https://example.com/waitlist?source=home", paidExperiment)).toContain("utm_campaign=exp-exp_paid");
  });

  it("removes customer identifiers from the model context", () => {
    const context = { cohort: "Activated", people: 240, email: "person@example.com", nested: { phone: "123" } };
    expect(hasRestrictedModelData(context)).toBe(true);
    expect(redactForModel(context)).toEqual({ cohort: "Activated", people: 240, nested: {} });
  });
});
