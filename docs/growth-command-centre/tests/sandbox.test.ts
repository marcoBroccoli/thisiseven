import { describe, expect, it } from "vitest";
import { createSandboxRun } from "../shared/sandbox";
import { demoGoal } from "../worker/demo";

describe("sandbox experiments", () => {
  it("produces a completed learning loop without an audience, spend, or provider", () => {
    const run = createSandboxRun(demoGoal, new Date("2026-07-28T10:00:00.000Z"));

    expect(run.experiment.channel).toBe("sandbox");
    expect(run.experiment.status).toBe("completed");
    expect(run.experiment.audienceId).toBeUndefined();
    expect(run.experiment.spend).toEqual({});
    expect(run.learningCard.outcome).toBe("win");
    expect(run.learningCard.evidence[0].detail).toContain("No customer, provider, or paid-channel data was used.");
  });
});
