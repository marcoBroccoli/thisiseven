import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Context } from "hono";
import { GoalInputSchema } from "../shared/contracts";
import { approvalIssues, canApproveExternalAction, canManageConnections, createApprovalSnapshot } from "../shared/safety";
import type { ExecutionJob, Experiment, Member } from "../shared/types";
import type { Env } from "./env";
import { weeklyProposal } from "./planner";
import { providerDefinition } from "./providers";
import { encryptConnectionConfig } from "./crypto";
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
  engineeringFlagRegistered,
  getExperiment,
  loadDashboard,
  markExperimentLive,
  markJob,
  memberForEmail,
  memberForSlack,
  registerSlackInteraction,
  storeConnectionConfig,
  transitionExperiment
} from "./store";
import { notifySlackApproval, verifySlackRequest } from "./slack";

type Variables = { actor: Member; workspaceId: string };
type AppContext = Context<{ Bindings: Env; Variables: Variables }>;
const app = new Hono<{ Bindings: Env; Variables: Variables }>();
app.use("/api/*", cors());

app.onError((error, context) => {
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

app.get("/api/health", (context) => context.json({ ok: true }));

app.get("/api/dashboard", async (context) => context.json(await loadDashboard(context.env.DB)));

app.post("/api/goals", async (context) => {
  const actor = context.get("actor");
  if (actor.role === "viewer") return context.json({ error: "Viewers cannot create goals." }, 403);
  const input = GoalInputSchema.parse(await context.req.json());
  const goal = await createGoal(context.env.DB, context.get("workspaceId"), input, actor.id);
  return context.json(goal, 201);
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
    const encrypted = await encryptConnectionConfig(context.env, config);
    await storeConnectionConfig(context.env.DB, context.get("workspaceId"), provider as Parameters<typeof connectionFor>[2], encrypted, actor.id);
    return context.json({ ok: true, message: "Configuration stored securely. Complete OAuth or provider access checks before enabling capabilities." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not store connection configuration.";
    return context.json({ error: message }, message.includes("encryption") ? 503 : 400);
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

async function runDailyMonitor(env: Env): Promise<void> {
  const dashboard = await loadDashboard(env.DB);
  await audit(env.DB, dashboard.workspace.id, undefined, "daily_monitor_completed", "workspace", dashboard.workspace.id, {
    sources: dashboard.connections.filter((connection) => connection.status === "connected").map((connection) => connection.provider),
    policy: "aggregate_only"
  });
}

async function runWeeklyPlan(env: Env, actorId = "system"): Promise<Experiment | undefined> {
  const dashboard = await loadDashboard(env.DB);
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
