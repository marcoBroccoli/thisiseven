import { Hono } from "hono";
import { cors } from "hono/cors";
import { ZodError } from "zod";
import type { Context } from "hono";
import { ExperimentCreateSchema, ExperimentDraftUpdateSchema, GoalInputSchema, MetricDefinitionInputSchema, PostHogConnectionConfigSchema } from "../shared/contracts";
import { approvalIssues, canApproveExternalAction, canManageConnections, createApprovalSnapshot } from "../shared/safety";
import { createSandboxRun } from "../shared/sandbox";
import type { ExecutionJob, Experiment, Member } from "../shared/types";
import type { Env } from "./env";
import { weeklyProposal } from "./planner";
import { providerDefinition } from "./providers";
import { decryptConnectionConfig, encryptConnectionConfig } from "./crypto";
import { PostHogAnalyticsProvider, type PostHogConnectionConfig } from "./posthog";
import {
  approveExperiment,
  audienceFor,
  audit,
  connectionFor,
  createEngineeringBrief,
  createExecutionJob,
  createExperiment,
  createGoal,
  createLearningCard,
  createMetricDefinition,
  createMetricSnapshot,
  encryptedConnectionConfig,
  engineeringFlagRegistered,
  getExperiment,
  loadDashboard,
  markExperimentLive,
  markConnectionVerified,
  markMetricSynced,
  markJob,
  memberForEmail,
  memberForSlack,
  metricDefinitionFor,
  metricSnapshotsFor,
  registerSlackInteraction,
  resetSandboxRecords,
  recordConnectionSync,
  storeConnectionConfig,
  startMetricSyncRun,
  finishMetricSyncRun,
  transitionExperiment,
  updateExperimentDraft
} from "./store";
import { notifySlackApproval, verifySlackRequest } from "./slack";

type Variables = { actor: Member; workspaceId: string };
type AppContext = Context<{ Bindings: Env; Variables: Variables }>;
const app = new Hono<{ Bindings: Env; Variables: Variables }>();
app.use("/api/*", cors());

const isSandboxMode = (env: Env) => env.SANDBOX_MODE === "true";

app.onError((error, context) => {
  if (error instanceof ZodError) return context.json({ error: "Invalid request.", issues: error.flatten() }, 400);
  console.error(error);
  return context.json({ error: error.message || "Unexpected server error" }, 500);
});

async function actorFor(request: Request, env: Env): Promise<Member> {
  const dashboard = await loadDashboard(env.DB);
  if (env.DEMO_MODE === "true") return dashboard.me;
  const email = request.headers.get("cf-access-authenticated-user-email");
  if (!email) throw new Error("Cloudflare Access identity is required.");
  const member = await memberForEmail(env.DB, email);
  if (!member) throw new Error("This Access identity is not invited to the workspace.");
  return member;
}

app.use("/api/*", async (context, next) => {
  try {
    const actor = await actorFor(context.req.raw, context.env);
    context.set("actor", actor);
    context.set("workspaceId", "workspace_demo");
    await next();
  } catch (error) {
    return context.json({ error: error instanceof Error ? error.message : "Unauthorized" }, 401);
  }
});

app.get("/api/health", (context) => context.json({ ok: true, sandboxMode: isSandboxMode(context.env) }));

app.get("/api/dashboard", async (context) => context.json(await loadDashboard(context.env.DB, isSandboxMode(context.env))));

app.get("/api/metrics/:id/snapshots", async (context) => {
  const metric = await metricDefinitionFor(context.env.DB, context.get("workspaceId"), context.req.param("id"));
  if (!metric) return context.json({ error: "Metric not found." }, 404);
  const rawLimit = Number(context.req.query("limit") ?? 90);
  const snapshots = await metricSnapshotsFor(context.env.DB, context.get("workspaceId"), metric.id, rawLimit);
  return context.json({ metric, snapshots });
});

app.post("/api/goals", async (context) => {
  const actor = context.get("actor");
  if (actor.role === "viewer") return context.json({ error: "Viewers cannot create goals." }, 403);
  const input = GoalInputSchema.parse(await context.req.json());
  const metric = input.metricDefinitionId
    ? await metricDefinitionFor(context.env.DB, context.get("workspaceId"), input.metricDefinitionId)
    : undefined;
  if (!metric && !isSandboxMode(context.env)) {
    return context.json({ error: "Choose a registered metric before creating a live goal." }, 409);
  }
  if (input.metricDefinitionId && !metric) return context.json({ error: "The selected metric was not found in this workspace." }, 404);
  if (metric && !isSandboxMode(context.env) && (metric.status !== "ready" || metric.trustLevel !== "observed")) {
    return context.json({ error: "This metric needs a connected, observed source before it can be used for a live goal." }, 409);
  }
  const goal = await createGoal(context.env.DB, context.get("workspaceId"), metric
    ? { ...input, metricDefinitionId: metric.id, metricKind: metric.kind, metricName: metric.name, unit: metric.unit }
    : input, actor.id);
  return context.json(goal, 201);
});

app.post("/api/metrics", async (context) => {
  const actor = context.get("actor");
  if (actor.role === "viewer") return context.json({ error: "Viewers cannot create metric definitions." }, 403);
  const input = MetricDefinitionInputSchema.parse(await context.req.json());
  const metric = await createMetricDefinition(context.env.DB, context.get("workspaceId"), input, actor.id);
  return context.json(metric, 201);
});

app.post("/api/experiments", async (context) => {
  const actor = context.get("actor");
  if (actor.role === "viewer") return context.json({ error: "Viewers cannot create experiments." }, 403);
  const input = ExperimentCreateSchema.parse(await context.req.json());
  const dashboard = await loadDashboard(context.env.DB);
  const goal = dashboard.goals.find((item) => item.id === input.goalId);
  if (!goal) return context.json({ error: "Choose a goal in this workspace." }, 409);
  const timestamp = new Date().toISOString();
  const experiment: Experiment = {
    id: `exp_${crypto.randomUUID()}`,
    goalId: goal.id,
    title: input.title,
    surface: input.surface,
    channel: input.channel,
    status: "proposed",
    hypothesis: input.hypothesis,
    channelRationale: input.channelRationale,
    expectedImpact: input.expectedImpact,
    confidence: input.confidence,
    audienceId: input.audienceId,
    optimizationMetric: goal.metricName,
    successRule: input.successRule,
    decisionWindowDays: input.decisionWindowDays,
    variants: input.variants,
    spend: input.spend,
    engineeringFlagKey: input.engineeringFlagKey,
    engineeringBrief: input.engineeringFlagKey ? `Register ${input.engineeringFlagKey} and its tracking contract before launch.` : undefined,
    createdAt: timestamp,
    updatedAt: timestamp
  };
  if (experiment.surface === "product") experiment.status = "awaiting_engineering";
  else {
    const connection = dashboard.connections.find((item) => item.provider === experiment.channel);
    const audience = dashboard.audiences.find((item) => item.id === experiment.audienceId);
    const issues = approvalIssues(experiment, connection?.capabilities ?? [], audience?.eligible ?? false, true);
    experiment.status = issues.length ? "blocked" : "awaiting_approval";
  }
  const learningCard = {
    id: `card_${crypto.randomUUID()}`,
    experimentId: experiment.id,
    evidence: [{
      id: `evidence_${crypto.randomUUID()}`,
      source: "workspace" as const,
      label: "User-created plan",
      detail: `Created manually to move ${goal.metricName}. It remains approval-gated and has not made an external change.`,
      capturedAt: timestamp
    }],
    expectedImpact: experiment.expectedImpact,
    confidence: experiment.confidence,
    outcome: "pending" as const,
    outcomeSummary: "Created by a workspace member and waiting for the next decision.",
    nextAction: experiment.status === "blocked" ? "Resolve the listed channel or budget requirement before approval." : experiment.status === "awaiting_engineering" ? "Register the product flag and tracking contract." : "Review the exact plan, then approve or revise it."
  };
  await createExperiment(context.env.DB, dashboard.workspace.id, experiment, actor.id);
  await createLearningCard(context.env.DB, dashboard.workspace.id, learningCard);
  if (experiment.status === "awaiting_engineering" && experiment.engineeringFlagKey) {
    await createEngineeringBrief(context.env.DB, dashboard.workspace.id, {
      id: `brief_${crypto.randomUUID()}`,
      experimentId: experiment.id,
      flagKey: experiment.engineeringFlagKey,
      variants: experiment.variants.map((item) => item.name),
      trackingRequirements: [goal.metricName],
      status: "waiting_for_engineering"
    });
  }
  await audit(context.env.DB, dashboard.workspace.id, actor.id, "experiment_created_manually", "experiment", experiment.id, { goalId: goal.id, channel: experiment.channel, externalWrites: false });
  return context.json(experiment, 201);
});

app.post("/api/sandbox/run", async (context) => {
  const actor = context.get("actor");
  if (!canApproveExternalAction(actor.role)) return context.json({ error: "Only admins can run a sandbox experiment." }, 403);
  if (!isSandboxMode(context.env)) return context.json({ error: "Sandbox mode is disabled for this workspace." }, 403);
  const dashboard = await loadDashboard(context.env.DB);
  const goal = dashboard.goals.find((item) => item.status === "active");
  if (!goal) return context.json({ error: "Create an active goal before running a sandbox experiment." }, 409);
  const run = createSandboxRun(goal);
  const snapshot = createApprovalSnapshot(run.experiment, actor.id, "No audience: local simulation");
  run.experiment.approvalSnapshot = snapshot;
  await createExperiment(context.env.DB, dashboard.workspace.id, run.experiment, actor.id);
  await createLearningCard(context.env.DB, dashboard.workspace.id, run.learningCard);
  await createMetricSnapshot(context.env.DB, dashboard.workspace.id, run.metricSnapshot);
  await markExperimentLive(context.env.DB, run.experiment.id, "sandbox", `sandbox_${run.experiment.id}`, undefined);
  await transitionExperiment(context.env.DB, run.experiment.id, "completed", actor.id, "sandbox_experiment_completed");
  await audit(context.env.DB, dashboard.workspace.id, actor.id, "sandbox_experiment_started", "experiment", run.experiment.id, {
    approvalFingerprint: snapshot.fingerprint,
    externalWrites: false,
    audienceResolved: false,
    spendCents: 0
  });
  return context.json({ experiment: run.experiment, learningCard: run.learningCard, simulated: true }, 201);
});

app.post("/api/sandbox/reset", async (context) => {
  const actor = context.get("actor");
  if (!canApproveExternalAction(actor.role)) return context.json({ error: "Only admins can reset sandbox records." }, 403);
  if (!isSandboxMode(context.env)) return context.json({ error: "Sandbox mode is disabled for this workspace." }, 403);
  await resetSandboxRecords(context.env.DB, context.get("workspaceId"), actor.id);
  return context.json({ ok: true });
});

app.put("/api/connections/:provider/config", async (context) => {
  const actor = context.get("actor");
  if (!canManageConnections(actor.role)) return context.json({ error: "Only admins can configure connections." }, 403);
  const provider = context.req.param("provider");
  try {
    providerDefinition(provider as Parameters<typeof providerDefinition>[0]);
  } catch {
    return context.json({ error: "Unknown provider." }, 404);
  }
  const config = await context.req.json<unknown>();
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    return context.json({ error: "Connection configuration must be an object." }, 400);
  }
  try {
    const validatedConfig = provider === "posthog" ? PostHogConnectionConfigSchema.parse(config) : config;
    const encrypted = await encryptConnectionConfig(context.env, validatedConfig);
    await storeConnectionConfig(context.env.DB, context.get("workspaceId"), provider as Parameters<typeof connectionFor>[2], encrypted, actor.id);
    return context.json({ ok: true, message: "Configuration stored securely. Complete OAuth or provider access checks before enabling capabilities." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not store connection configuration.";
    return context.json({ error: message }, message.includes("encryption") ? 503 : 400);
  }
});

app.post("/api/connections/posthog/verify", async (context) => {
  const actor = context.get("actor");
  if (!canManageConnections(actor.role)) return context.json({ error: "Only admins can verify connections." }, 403);
  if (isSandboxMode(context.env)) return context.json({ error: "Sandbox mode blocks live provider reads. Turn it off in a deployed workspace before verifying PostHog." }, 409);
  const workspaceId = context.get("workspaceId");
  const encrypted = await encryptedConnectionConfig(context.env.DB, workspaceId, "posthog");
  if (!encrypted) return context.json({ error: "Store PostHog configuration before verification." }, 409);
  try {
    const config = PostHogConnectionConfigSchema.parse(await decryptConnectionConfig<PostHogConnectionConfig>(context.env, encrypted));
    const insights = await new PostHogAnalyticsProvider(config).listInsights();
    await markConnectionVerified(
      context.env.DB,
      workspaceId,
      "posthog",
      ["read_analytics"],
      `Read-only analytics verified. ${insights.length} saved insight${insights.length === 1 ? "" : "s"} discovered.`,
      actor.id
    );
    return context.json({ ok: true, insights });
  } catch (error) {
    const message = error instanceof Error ? error.message : "PostHog verification failed.";
    await recordConnectionSync(context.env.DB, workspaceId, "posthog", message);
    return context.json({ error: message }, 400);
  }
});

app.get("/api/connections/posthog/insights", async (context) => {
  const actor = context.get("actor");
  if (actor.role === "viewer") return context.json({ error: "Viewers cannot inspect connection metadata." }, 403);
  if (isSandboxMode(context.env)) return context.json({ error: "Sandbox mode does not read live PostHog data." }, 409);
  const workspaceId = context.get("workspaceId");
  const connection = await connectionFor(context.env.DB, workspaceId, "posthog");
  const encrypted = await encryptedConnectionConfig(context.env.DB, workspaceId, "posthog");
  if (connection?.status !== "connected" || !encrypted) return context.json({ error: "Verify the PostHog connection before discovering saved insights." }, 409);
  try {
    const config = PostHogConnectionConfigSchema.parse(await decryptConnectionConfig<PostHogConnectionConfig>(context.env, encrypted));
    const insights = await new PostHogAnalyticsProvider(config).listInsights();
    return context.json({ insights });
  } catch (error) {
    const message = error instanceof Error ? error.message : "PostHog insight discovery failed.";
    await recordConnectionSync(context.env.DB, workspaceId, "posthog", message);
    return context.json({ error: message }, 400);
  }
});

async function approve(context: AppContext, experimentId: string, actor: Member) {
  if (!canApproveExternalAction(actor.role)) return { error: "Only admins can approve an external action.", status: 403 };
  const found = await getExperiment(context.env.DB, experimentId);
  if (!found) return { error: "Experiment not found.", status: 404 };
  const connection = await connectionFor(context.env.DB, found.workspaceId, found.experiment.channel);
  const audience = await audienceFor(context.env.DB, found.experiment.audienceId);
  const flagRegistered = await engineeringFlagRegistered(context.env.DB, found.experiment.id);
  const issues = approvalIssues(found.experiment, connection?.capabilities ?? [], audience?.eligible ?? false, flagRegistered);
  if (issues.length) return { error: "Experiment is not ready for approval.", issues, status: 409 };
  const snapshot = createApprovalSnapshot(found.experiment, actor.id, audience?.name);
  await approveExperiment(context.env.DB, found.workspaceId, found.experiment, snapshot, actor.id);
  const job = await createExecutionJob(context.env.DB, found.workspaceId, found.experiment.id, snapshot.fingerprint);
  if (job.created) {
    await context.env.EXECUTION_QUEUE.send({ id: job.id, experimentId: found.experiment.id, approvalFingerprint: snapshot.fingerprint, kind: "publish" });
  }
  await transitionExperiment(context.env.DB, found.experiment.id, "queued", actor.id, "experiment_queued");
  return { snapshot, job, status: 200 };
}

app.post("/api/experiments/:id/approve", async (context) => {
  const result = await approve(context, context.req.param("id"), context.get("actor"));
  return "error" in result ? context.json(result, result.status as 403 | 404 | 409) : context.json(result);
});

app.post("/api/experiments/:id/reject", async (context) => {
  const actor = context.get("actor");
  if (!canApproveExternalAction(actor.role)) return context.json({ error: "Only admins can reject an external action." }, 403);
  await transitionExperiment(context.env.DB, context.req.param("id"), "cancelled", actor.id, "experiment_rejected");
  return context.json({ ok: true });
});

app.put("/api/experiments/:id", async (context) => {
  const actor = context.get("actor");
  if (actor.role === "viewer") return context.json({ error: "Viewers cannot edit experiments." }, 403);
  const experimentId = context.req.param("id");
  const found = await getExperiment(context.env.DB, experimentId);
  if (!found || found.workspaceId !== context.get("workspaceId")) return context.json({ error: "Experiment not found." }, 404);
  const update = ExperimentDraftUpdateSchema.parse(await context.req.json());
  const experiment = await updateExperimentDraft(context.env.DB, experimentId, update, actor.id);
  return context.json(experiment);
});

async function syncPostHogMetrics(env: Env, dashboard: Awaited<ReturnType<typeof loadDashboard>>): Promise<{ status: "skipped" | "completed" | "failed"; synced: number; error?: string }> {
  if (isSandboxMode(env)) return { status: "skipped", synced: 0, error: "Sandbox mode blocks live provider reads." };
  const connection = await connectionFor(env.DB, dashboard.workspace.id, "posthog");
  const metrics = dashboard.metricDefinitions.filter((metric) => metric.sourceProvider === "posthog" && metric.status === "ready" && metric.trustLevel === "observed" && metric.sourceMetricId);
  if (!connection || connection.status !== "connected" || !connection.capabilities.includes("read_analytics")) {
    return { status: "skipped", synced: 0, error: "PostHog read access is not verified." };
  }
  if (!metrics.length) return { status: "skipped", synced: 0, error: "No ready PostHog metric is mapped to a saved insight." };
  const encrypted = await encryptedConnectionConfig(env.DB, dashboard.workspace.id, "posthog");
  if (!encrypted) return { status: "failed", synced: 0, error: "PostHog configuration is missing." };

  const syncRunId = await startMetricSyncRun(env.DB, dashboard.workspace.id, "posthog", new Date().toISOString().slice(0, 10));
  try {
    const config = PostHogConnectionConfigSchema.parse(await decryptConnectionConfig<PostHogConnectionConfig>(env, encrypted));
    const provider = new PostHogAnalyticsProvider(config);
    let synced = 0;
    const errors: string[] = [];
    for (const metric of metrics) {
      try {
        const point = await provider.latestAggregate(metric.sourceMetricId!);
        if (!point) {
          errors.push(`${metric.name}: no aggregate result`);
          continue;
        }
        const capturedAt = point.capturedAt ?? new Date().toISOString();
        const created = await createMetricSnapshot(env.DB, dashboard.workspace.id, {
          id: `snapshot_${crypto.randomUUID()}`,
          metricDefinitionId: metric.id,
          sourceProvider: "posthog",
          value: point.value,
          dimensions: { insightId: metric.sourceMetricId!, ...(point.label ? { series: point.label } : {}) },
          trustLevel: "observed",
          quality: "verified",
          capturedAt
        });
        await markMetricSynced(env.DB, dashboard.workspace.id, metric.id, capturedAt);
        if (created) synced += 1;
      } catch (error) {
        errors.push(`${metric.name}: ${error instanceof Error ? error.message : "snapshot failed"}`);
      }
    }
    const error = errors.length ? errors.join("; ") : undefined;
    await recordConnectionSync(env.DB, dashboard.workspace.id, "posthog", error);
    await finishMetricSyncRun(env.DB, syncRunId, error);
    return { status: error ? "failed" : "completed", synced, error };
  } catch (error) {
    const message = error instanceof Error ? error.message : "PostHog metric sync failed.";
    await recordConnectionSync(env.DB, dashboard.workspace.id, "posthog", message);
    await finishMetricSyncRun(env.DB, syncRunId, message);
    return { status: "failed", synced: 0, error: message };
  }
}

async function runDailyMonitor(env: Env): Promise<void> {
  const dashboard = await loadDashboard(env.DB, isSandboxMode(env));
  const posthog = await syncPostHogMetrics(env, dashboard);
  await audit(env.DB, dashboard.workspace.id, undefined, "daily_monitor_completed", "workspace", dashboard.workspace.id, {
    sources: dashboard.connections.filter((connection) => connection.status === "connected").map((connection) => connection.provider),
    policy: "aggregate_only",
    posthog
  });
}

async function runWeeklyPlan(env: Env, actorId = "system"): Promise<Experiment | undefined> {
  const dashboard = await loadDashboard(env.DB, isSandboxMode(env));
  const goal = dashboard.goals.find((item) => item.status === "active");
  if (!goal) return undefined;
  const { experiment, learningCard } = await weeklyProposal(env, dashboard, goal);
  await createExperiment(env.DB, dashboard.workspace.id, experiment, actorId);
  await createLearningCard(env.DB, dashboard.workspace.id, learningCard);
  if (experiment.status === "awaiting_engineering" && experiment.engineeringFlagKey) {
    await createEngineeringBrief(env.DB, dashboard.workspace.id, {
      id: `brief_${crypto.randomUUID()}`,
      experimentId: experiment.id,
      flagKey: experiment.engineeringFlagKey,
      variants: ["control", "treatment"],
      trackingRequirements: [experiment.optimizationMetric, "guardrail_metric"],
      status: "waiting_for_engineering"
    });
  } else {
    const connection = await connectionFor(env.DB, dashboard.workspace.id, experiment.channel);
    const audience = await audienceFor(env.DB, experiment.audienceId);
    const issues = approvalIssues(experiment, connection?.capabilities ?? [], audience?.eligible ?? false, true);
    if (issues.length) await transitionExperiment(env.DB, experiment.id, "blocked", actorId, "proposal_blocked");
    else {
      await transitionExperiment(env.DB, experiment.id, "awaiting_approval", actorId, "proposal_ready_for_approval");
      await notifySlackApproval(env, experiment);
    }
  }
  await audit(env.DB, dashboard.workspace.id, actorId, "weekly_plan_completed", "workspace", dashboard.workspace.id, { experimentId: experiment.id });
  return experiment;
}

app.post("/api/automation/daily-monitor", async (context) => {
  if (!canApproveExternalAction(context.get("actor").role)) return context.json({ error: "Only admins can run automation." }, 403);
  await runDailyMonitor(context.env);
  return context.json({ ok: true });
});

app.post("/api/automation/weekly-plan", async (context) => {
  if (!canApproveExternalAction(context.get("actor").role)) return context.json({ error: "Only admins can run automation." }, 403);
  const experiment = await runWeeklyPlan(context.env, context.get("actor").id);
  return context.json({ experiment });
});

app.post("/slack/interactions", async (context) => {
  const body = await context.req.text();
  const valid = await verifySlackRequest(context.req.raw, body, context.env.SLACK_SIGNING_SECRET);
  if (!valid && context.env.DEMO_MODE !== "true") return context.text("Invalid Slack signature", 401);
  const encoded = new URLSearchParams(body).get("payload");
  if (!encoded) return context.text("Missing Slack payload", 400);
  const payload = JSON.parse(encoded) as { user?: { id?: string }; actions?: { action_id?: string; action_ts?: string; value?: string }[] };
  const action = payload.actions?.[0];
  const slackUserId = payload.user?.id;
  if (!action || !slackUserId || !action.value) return context.text("Malformed Slack action", 400);
  const value = JSON.parse(action.value) as { experimentId?: string };
  if (!value.experimentId) return context.text("Missing experiment", 400);
  const member = await memberForSlack(context.env.DB, slackUserId) ?? (context.env.DEMO_MODE === "true" ? (await loadDashboard(context.env.DB)).me : undefined);
  if (!member) return context.json({ response_type: "ephemeral", text: "You are not an invited member of this workspace." });
  const actionId = `${slackUserId}:${action.action_ts ?? crypto.randomUUID()}`;
  const fresh = await registerSlackInteraction(context.env.DB, actionId, "workspace_demo", slackUserId, payload);
  if (!fresh) return context.json({ response_type: "ephemeral", text: "That decision was already processed." });
  if (action.action_id === "growth.approve") {
    const result = await approve(context, value.experimentId, member);
    return "error" in result
      ? context.json({ response_type: "ephemeral", text: result.error })
      : context.json({ response_type: "in_channel", replace_original: true, text: `Approved by ${member.name}. Execution was queued.` });
  }
  if (action.action_id === "growth.reject") {
    if (!canApproveExternalAction(member.role)) return context.json({ response_type: "ephemeral", text: "Only admins can reject external actions." });
    await transitionExperiment(context.env.DB, value.experimentId, "cancelled", member.id, "experiment_rejected_in_slack");
    return context.json({ response_type: "in_channel", replace_original: true, text: `Rejected by ${member.name}.` });
  }
  return context.json({ response_type: "ephemeral", text: "That Slack action is not supported." });
});

async function executeJob(job: ExecutionJob, env: Env): Promise<void> {
  if (job.kind !== "publish") return;
  const found = await getExperiment(env.DB, job.experimentId);
  if (!found) {
    await markJob(env.DB, job.id, "failed", "Experiment was deleted before execution.");
    return;
  }
  if (found.experiment.approvalSnapshot?.fingerprint !== job.approvalFingerprint) {
    await markJob(env.DB, job.id, "failed", "The approval snapshot no longer matches this job.");
    return;
  }
  if (isSandboxMode(env)) {
    await markJob(env.DB, job.id, "failed", "Sandbox mode blocks all non-sandbox provider execution.");
    await transitionExperiment(env.DB, found.experiment.id, "blocked", "system", "sandbox_execution_blocked");
    return;
  }
  const connection = await connectionFor(env.DB, found.workspaceId, found.experiment.channel);
  const capability = found.experiment.surface === "email" ? "send_email" : found.experiment.surface === "product" ? "create_product_experiment" : found.experiment.surface === "paid" ? "create_campaign" : "publish_organic";
  if (!connection?.capabilities.includes(capability)) {
    await markJob(env.DB, job.id, "failed", "Provider authorization changed before execution.");
    await transitionExperiment(env.DB, found.experiment.id, "blocked", "system", "execution_blocked");
    return;
  }
  if (env.DEMO_MODE === "true") {
    await markExperimentLive(env.DB, found.experiment.id, found.experiment.channel, `demo_${job.id}`, `https://demo.local/publications/${job.id}`);
    await markJob(env.DB, job.id, "completed");
    return;
  }
  await markJob(env.DB, job.id, "failed", `The ${providerDefinition(found.experiment.channel).label} live executor is not configured for this workspace.`);
  await transitionExperiment(env.DB, found.experiment.id, "blocked", "system", "execution_requires_provider_configuration");
}

export default {
  fetch: app.fetch,
  async queue(batch: MessageBatch<ExecutionJob>, env: Env): Promise<void> {
    for (const message of batch.messages) {
      try {
        await executeJob(message.body, env);
        message.ack();
      } catch (error) {
        console.error(error);
        message.retry();
      }
    }
  },
  async scheduled(controller: ScheduledController, env: Env, execution: ExecutionContext): Promise<void> {
    if (controller.cron.includes("MON")) execution.waitUntil(runWeeklyPlan(env));
    else execution.waitUntil(runDailyMonitor(env));
  }
};

export { app };
