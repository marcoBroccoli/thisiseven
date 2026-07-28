import { describe, expect, it } from "vitest";
import { recordConnectionSync } from "../worker/store";

function databaseSpy() {
  const calls: Array<{ sql: string; values: unknown[] }> = [];
  const db = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          calls.push({ sql, values });
          return { run: async () => ({ success: true }) };
        }
      };
    }
  } as unknown as D1Database;
  return { db, calls };
}

describe("connection sync state", () => {
  it("retains the last successful timestamp when a later sync fails", async () => {
    const { db, calls } = databaseSpy();

    await recordConnectionSync(db, "workspace_1", "posthog", "PostHog rate limited this read.");

    expect(calls).toHaveLength(1);
    expect(calls[0].sql).not.toContain("last_synced_at = ?");
    expect(calls[0].sql).toContain("sync_error = ?");
    expect(calls[0].values).toContain("PostHog rate limited this read.");
  });

  it("clears the sync error only after a successful sync", async () => {
    const { db, calls } = databaseSpy();

    await recordConnectionSync(db, "workspace_1", "posthog");

    expect(calls).toHaveLength(1);
    expect(calls[0].sql).toContain("last_synced_at = ?");
    expect(calls[0].sql).toContain("sync_error = NULL");
  });
});
