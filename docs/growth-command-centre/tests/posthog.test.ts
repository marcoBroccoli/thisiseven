import { describe, expect, it } from "vitest";
import { aggregatePointsFromInsight, PostHogAnalyticsProvider } from "../worker/posthog";

describe("PostHog analytics provider", () => {
  it("lists saved insights using a server-side bearer token", async () => {
    let request: Request | undefined;
    const provider = new PostHogAnalyticsProvider(
      { host: "https://eu.posthog.com", projectId: "42", personalApiKey: "phx_read_only" },
      { fetcher: async (input, init) => {
        request = new Request(input, init);
        return Response.json({ results: [{ id: 14, name: "Activated workspaces", description: "Daily activation" }] });
      } }
    );

    await expect(provider.listInsights()).resolves.toEqual([{ id: "14", name: "Activated workspaces", description: "Daily activation", kind: undefined }]);
    expect(request?.url).toBe("https://eu.posthog.com/api/projects/42/insights/?limit=100");
    expect(request?.headers.get("authorization")).toBe("Bearer phx_read_only");
  });

  it("extracts only aggregate result points from an insight response", () => {
    const points = aggregatePointsFromInsight({
      result: [{ data: [{ date: "2026-07-26", count: 31 }, { date: "2026-07-27", count: 34 }] }],
      people: [{ email: "must-not-be-read@example.com" }]
    });

    expect(points).toEqual([
      { value: 31, capturedAt: "2026-07-26T00:00:00.000Z", label: "2026-07-26" },
      { value: 34, capturedAt: "2026-07-27T00:00:00.000Z", label: "2026-07-27" }
    ]);
  });

  it("returns a safe error when PostHog rejects an unavailable key", async () => {
    const provider = new PostHogAnalyticsProvider(
      { host: "https://eu.posthog.com", projectId: "42", personalApiKey: "phx_read_only" },
      { fetcher: async () => new Response("", { status: 403 }) }
    );
    await expect(provider.listInsights()).rejects.toThrow("insight:read permission");
  });
});
