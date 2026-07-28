import { useEffect, useMemo, useState } from "react";
import {
  Activity,
  ArrowUpRight,
  BarChart3,
  BellRing,
  Bot,
  Check,
  ChevronRight,
  CircleAlert,
  Clock3,
  Eye,
  FlaskConical,
  Goal as GoalIcon,
  ImagePlus,
  Layers3,
  Link2,
  LoaderCircle,
  Menu,
  MoreHorizontal,
  Plus,
  Radio,
  RefreshCw,
  Send,
  Settings2,
  ShieldCheck,
  Slack,
  Sparkles,
  Target,
  UsersRound,
  X
} from "lucide-react";
import { demoDashboard } from "../worker/demo";
import { api } from "./api";
import { freshnessLabels, latestSnapshot, metricIsLive, qualityLabels, trustLabels } from "../shared/measurement";
import type { DashboardPayload, Experiment, ExperimentCreateInput, ExperimentDraftUpdate, Goal, MetricDefinition, MetricDefinitionInput, MetricSnapshot, PostHogInsight, ProviderConnection } from "../shared/types";

type View = "command" | "metrics" | "channels" | "data" | "experiments" | "learning" | "connections";
type Toast = { tone: "success" | "error" | "neutral"; message: string } | undefined;

const statusLabel: Record<Experiment["status"], string> = {
  proposed: "Proposed",
  needs_changes: "Needs changes",
  awaiting_engineering: "Engineering",
  awaiting_approval: "Approval",
  approved: "Approved",
  queued: "Queued",
  live: "Live",
  measuring: "Measuring",
  completed: "Complete",
  failed: "Failed",
  cancelled: "Cancelled",
  blocked: "Blocked"
};

function formatCents(value?: number): string {
  if (!value) return "No paid budget";
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "EUR", maximumFractionDigits: 0 }).format(value / 100);
}

function dateLabel(value?: string): string {
  if (!value) return "Not run yet";
  return new Intl.DateTimeFormat("en", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

function formatMetricValue(value: number | undefined, unit: string): string {
  if (value === undefined) return "Not measured";
  return `${new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(value)}${unit}`;
}

function measurementForGoal(dashboard: DashboardPayload, goal: Goal) {
  const definition = dashboard.metricDefinitions.find((metric) => metric.id === goal.metricDefinitionId) ?? dashboard.metricDefinitions.find((metric) => metric.name === goal.metricName);
  const snapshot = latestSnapshot(dashboard.metricSnapshots, definition?.id);
  const source = snapshot ? dashboard.dataSources.find((item) => item.provider === snapshot.sourceProvider) : definition ? dashboard.dataSources.find((item) => item.provider === definition.sourceProvider) : undefined;
  return { definition, snapshot, source, live: metricIsLive(definition, snapshot) };
}

export function App() {
  const [dashboard, setDashboard] = useState<DashboardPayload>(demoDashboard);
  const [view, setView] = useState<View>("command");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string>();
  const [toast, setToast] = useState<Toast>();
  const [showGoalForm, setShowGoalForm] = useState(false);
  const [mobileNavOpen, setMobileNavOpen] = useState(false);
  const [selectedExperimentId, setSelectedExperimentId] = useState<string>();
  const [editingExperiment, setEditingExperiment] = useState<Experiment>();
  const [showExperimentForm, setShowExperimentForm] = useState(false);
  const [showMetricForm, setShowMetricForm] = useState(false);
  const [showPostHogSetup, setShowPostHogSetup] = useState(false);
  const [selectedMetricId, setSelectedMetricId] = useState<string>();

  const refresh = async () => {
    try {
      const payload = await api.dashboard();
      setDashboard(payload);
    } catch {
      setToast({ tone: "neutral", message: "Showing the local demo workspace until the Worker API is running." });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void refresh(); }, []);

  const run = async (key: string, action: () => Promise<unknown>, success: string) => {
    setBusy(key);
    try {
      await action();
      await refresh();
      setToast({ tone: "success", message: success });
      return true;
    } catch (error) {
      setToast({ tone: "error", message: error instanceof Error ? error.message : "That action could not be completed." });
      return false;
    } finally {
      setBusy(undefined);
    }
  };

  const activeGoal = dashboard.goals.find((goal) => goal.status === "active") ?? dashboard.goals[0];
  const selectedExperiment = useMemo(
    () => dashboard.experiments.find((experiment) => experiment.status === "awaiting_approval"),
    [dashboard.experiments]
  );
  const openExperiment = (experimentId: string) => {
    setSelectedExperimentId(experimentId);
    setView("experiments");
  };
  const openMetric = (metricId: string) => {
    setSelectedMetricId(metricId);
    setView("metrics");
  };

  return (
    <div className="app-shell">
      <aside className={`sidebar ${mobileNavOpen ? "sidebar-open" : ""}`} aria-label="Primary navigation">
        <div className="brand-row">
          <div className="brand-mark" aria-hidden="true"><Sparkles size={18} /></div>
          <div>
            <strong>Entrepreneurial</strong>
            <span>Command centre</span>
          </div>
          <button className="icon-button mobile-only" onClick={() => setMobileNavOpen(false)} aria-label="Close navigation"><X size={18} /></button>
        </div>
        <div className="workspace-switcher">
          <div className="workspace-avatar">N</div>
          <div><strong>{dashboard.workspace.productName}</strong><span>Private workspace</span></div>
          <ChevronRight size={16} />
        </div>
        <nav>
          <NavButton icon={<Layers3 size={18} />} label="Command" active={view === "command"} onClick={() => setView("command")} />
          <NavButton icon={<BarChart3 size={18} />} label="Metrics" active={view === "metrics"} onClick={() => setView("metrics")} />
          <NavButton icon={<Radio size={18} />} label="Channels" active={view === "channels"} onClick={() => setView("channels")} />
          <NavButton icon={<Settings2 size={18} />} label="Data" active={view === "data"} onClick={() => setView("data")} />
          <NavButton icon={<FlaskConical size={18} />} label="Experiments" count={dashboard.experiments.filter((item) => item.status === "awaiting_approval").length} active={view === "experiments"} onClick={() => setView("experiments")} />
          <NavButton icon={<BookIcon />} label="Learning" active={view === "learning"} onClick={() => setView("learning")} />
          <NavButton icon={<Link2 size={18} />} label="Connections" active={view === "connections"} onClick={() => setView("connections")} />
        </nav>
        <div className="sidebar-bottom">
          <div className="member-chip"><div className="member-avatar">{dashboard.me.name.slice(0, 1)}</div><div><strong>{dashboard.me.name}</strong><span>{dashboard.me.role}</span></div></div>
        </div>
      </aside>

      <main className="main-content">
        <header className="topbar">
          <button className="icon-button mobile-only" onClick={() => setMobileNavOpen(true)} aria-label="Open navigation"><Menu size={20} /></button>
          <div className="topbar-title"><span className="eyebrow">{view === "command" ? "Growth operating system" : view}</span><h1>{titleFor(view)}</h1></div>
          <div className="topbar-actions">
            <div className="status-note"><span className="status-dot" />{dashboard.sandboxMode ? "Sandbox measurements only" : `Data refreshed ${dateLabel(dashboard.lastDailyMonitorAt)}`}</div>
            <button className="icon-button" title="Refresh workspace" onClick={() => void refresh()} disabled={loading}><RefreshCw size={18} className={loading ? "spin" : ""} /></button>
            <button className="primary-button" onClick={() => setShowGoalForm(true)}><Plus size={18} /> New goal</button>
          </div>
        </header>

        {toast && <div className={`toast toast-${toast.tone}`} role="status">{toast.tone === "success" ? <Check size={16} /> : toast.tone === "error" ? <CircleAlert size={16} /> : <BellRing size={16} />}{toast.message}<button onClick={() => setToast(undefined)} aria-label="Dismiss"><X size={15} /></button></div>}
        {dashboard.sandboxMode && <section className="sandbox-notice" aria-label="Sandbox mode active"><div><FlaskConical size={17} /><span><strong>Sandbox mode active</strong> All test experiments stay local. Provider publication, audience resolution, and spend are blocked.</span></div><button className="text-button" disabled={busy === "sandbox-reset"} onClick={() => void run("sandbox-reset", api.resetSandbox, "Sandbox records reset. No production data was changed.")}>Reset test data</button></section>}

        {view === "command" && activeGoal && <CommandView
          goal={activeGoal}
          experiment={selectedExperiment}
          dashboard={dashboard}
          busy={busy}
          onMonitor={() => void run("monitor", api.monitor, "Daily monitor completed. Slack will receive any urgent attention items.")}
          onPlan={() => void run("plan", api.weeklyPlan, "A new weekly experiment proposal was generated.")}
          onSandbox={() => void run("sandbox", api.runSandbox, "Sandbox complete. No provider, audience, or budget was used.")}
          onApprove={(experiment) => void run(`approve-${experiment.id}`, () => api.approve(experiment.id), "Approved and queued. The provider will not receive a duplicate launch request.")}
          onReject={(experiment) => void run(`reject-${experiment.id}`, () => api.reject(experiment.id), "Experiment rejected and removed from the approval queue.")}
          onViewExperiments={() => setView("experiments")}
        />}
        {view === "metrics" && <MetricsView dashboard={dashboard} selectedMetricId={selectedMetricId} onCloseMetric={() => setSelectedMetricId(undefined)} onOpenMetric={openMetric} onOpenExperiment={openExperiment} />}
        {view === "channels" && <ChannelsView dashboard={dashboard} onOpenExperiment={openExperiment} />}
        {view === "data" && <DataView dashboard={dashboard} onCreateMetric={() => setShowMetricForm(true)} onOpenMetric={openMetric} />}
        {view === "experiments" && <ExperimentsView dashboard={dashboard} busy={busy} selectedExperimentId={selectedExperimentId} onSelect={setSelectedExperimentId} onCreate={() => setShowExperimentForm(true)} onEdit={setEditingExperiment} onApprove={(experiment) => void run(`approve-${experiment.id}`, () => api.approve(experiment.id), "Approved and queued for execution.")} onReject={(experiment) => void run(`reject-${experiment.id}`, () => api.reject(experiment.id), "Experiment rejected.")} onOpenConnections={() => setView("connections")} />}
        {view === "learning" && <LearningView dashboard={dashboard} onOpenExperiment={openExperiment} />}
        {view === "connections" && <ConnectionsView connections={dashboard.connections} sandboxMode={dashboard.sandboxMode} onSetupPostHog={() => setShowPostHogSetup(true)} />}
      </main>

      {showGoalForm && <GoalForm metricDefinitions={dashboard.metricDefinitions} sandboxMode={dashboard.sandboxMode} onClose={() => setShowGoalForm(false)} onSubmit={(goal) => { void run("goal", () => api.createGoal(goal), "Goal created. It will be included in the next weekly plan.").then((created) => { if (created) setShowGoalForm(false); }); }} />}
      {showMetricForm && <MetricDefinitionForm dataSources={dashboard.dataSources} sandboxMode={dashboard.sandboxMode} onClose={() => setShowMetricForm(false)} onSubmit={(metric) => { void run("metric", () => api.createMetric(metric), "Metric definition created. Connect its source before using it in a live goal.").then((created) => { if (created) setShowMetricForm(false); }); }} />}
      {showPostHogSetup && <PostHogConnectionForm sandboxMode={dashboard.sandboxMode} onClose={() => setShowPostHogSetup(false)} onSubmit={(config) => { void run("posthog-setup", async () => { await api.configureConnection("posthog", config); await api.verifyPostHog(); }, "PostHog read access verified. Choose a saved insight when defining a metric.").then((completed) => { if (completed) setShowPostHogSetup(false); }); }} />}
      {showExperimentForm && <ExperimentCreateForm goals={dashboard.goals} audiences={dashboard.audiences} onClose={() => setShowExperimentForm(false)} onSubmit={(experiment) => { void run("experiment-create", () => api.createExperiment(experiment), "Experiment created. No provider action was taken.").then((created) => { if (created) setShowExperimentForm(false); }); }} />}
      {editingExperiment && <ExperimentEditForm experiment={editingExperiment} audiences={dashboard.audiences} onClose={() => setEditingExperiment(undefined)} onSubmit={(update) => { void run(`edit-${editingExperiment.id}`, () => api.updateExperiment(editingExperiment.id, update), "Proposal updated. Nothing was published.").then((updated) => { if (updated) setEditingExperiment(undefined); }); }} />}
    </div>
  );
}

function CommandView({ goal, experiment, dashboard, busy, onMonitor, onPlan, onSandbox, onApprove, onReject, onViewExperiments }: {
  goal: Goal; experiment?: Experiment; dashboard: DashboardPayload; busy?: string; onMonitor: () => void; onPlan: () => void; onSandbox: () => void; onApprove: (experiment: Experiment) => void; onReject: (experiment: Experiment) => void; onViewExperiments: () => void;
}) {
  const measurement = measurementForGoal(dashboard, goal);
  const current = measurement.snapshot?.value;
  const progress = current === undefined || goal.target === goal.baseline ? 0 : Math.min(100, Math.max(0, ((current - goal.baseline) / (goal.target - goal.baseline)) * 100));
  const ready = dashboard.experiments.filter((item) => item.status === "awaiting_approval").length;
  const live = dashboard.experiments.filter((item) => item.status === "live").length;
  return <div className="view-stack">
    <section className="goal-band">
      <div className="goal-copy"><span className="eyebrow"><Target size={14} /> Active outcome</span><h2>{goal.title}</h2><p>Metric: <strong>{goal.metricName}</strong>. Move it from {formatMetricValue(goal.baseline, goal.unit)} to {formatMetricValue(goal.target, goal.unit)} by {new Intl.DateTimeFormat("en", { month: "long", day: "numeric" }).format(new Date(goal.deadline))}.</p></div>
      <div className="goal-measure"><div className="goal-numbers"><strong>{formatMetricValue(current, goal.unit)}</strong><span>{measurement.snapshot ? `${trustLabels[measurement.snapshot.trustLevel]} measurement` : "No measurement"}</span><ArrowUpRight size={18} /><strong>{formatMetricValue(goal.target, goal.unit)}</strong><span>target</span></div><div className="progress-track"><div style={{ width: `${Math.max(8, progress)}%` }} /></div><small>{measurement.snapshot ? `${measurement.source?.label ?? measurement.snapshot.sourceProvider} · ${qualityLabels[measurement.snapshot.quality]} · ${dateLabel(measurement.snapshot.capturedAt)}` : dashboard.sandboxMode ? "No live data is used in Sandbox. Connect a source to measure this goal." : goal.guardrail}</small></div>
    </section>
    <section className="decision-guide" aria-label="Next action">
      <div className="decision-copy"><span className="eyebrow">Your next action</span><h3>{dashboard.sandboxMode ? "Run a safe workflow test" : experiment ? "Review the pending experiment" : "Draft the next experiment"}</h3><p>{dashboard.sandboxMode ? "Creates a simulated experiment, publication, metric result, and learning card. It sends nothing, spends nothing, and does not use customer data. Refresh measurements is read-only; drafting creates a review-only proposal." : experiment ? "Review the hypothesis, audience, metric, and expected impact before approving any external action." : "Creates an editable proposal from the available aggregate evidence. It does not publish anything."}</p></div>
      <div className="decision-actions"><button className="primary-button" disabled={busy === "sandbox" || busy === "plan"} onClick={dashboard.sandboxMode ? onSandbox : experiment ? onViewExperiments : onPlan}>{busy === "sandbox" || busy === "plan" ? <LoaderCircle className="spin" size={17} /> : dashboard.sandboxMode ? <FlaskConical size={17} /> : experiment ? <FlaskConical size={17} /> : <Bot size={17} />}{dashboard.sandboxMode ? "Run test experiment" : experiment ? "Review experiment" : "Draft experiment"}</button><div className="secondary-actions"><button className="text-button" title="Read measurements only; does not publish or spend" disabled={busy === "monitor"} onClick={onMonitor}>{busy === "monitor" ? <LoaderCircle className="spin" size={15} /> : <RefreshCw size={15} />} Refresh measurements</button><button className="text-button" title="Create a review-only proposal; does not publish" disabled={busy === "plan"} onClick={onPlan}><Bot size={15} /> Draft next experiment</button></div></div>
    </section>
    <section className="metric-grid" aria-label="Growth summary">
      <MetricCard icon={<Target size={19} />} label={measurement.live ? "Observed metric" : "Measurement state"} value={formatMetricValue(current, goal.unit)} detail={measurement.snapshot ? `${trustLabels[measurement.snapshot.trustLevel]} · ${qualityLabels[measurement.snapshot.quality]}` : "No metric snapshot"} tone="teal" />
      <MetricCard icon={<ArrowUpRight size={19} />} label="Target" value={formatMetricValue(goal.target, goal.unit)} detail={`Deadline: ${new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(new Date(goal.deadline))}`} tone="blue" />
      <MetricCard icon={<FlaskConical size={19} />} label="Decision queue" value={String(ready)} detail={dashboard.sandboxMode ? "External actions locked in Sandbox" : ready ? "Needs an admin decision" : "No external action waiting"} tone="amber" />
      <MetricCard icon={dashboard.sandboxMode ? <ShieldCheck size={19} /> : <BarChart3 size={19} />} label="Action impact" value={dashboard.sandboxMode ? "Safe" : formatCents(goal.monthlyBudgetCents)} detail={dashboard.sandboxMode ? "No provider, audience, or spend" : "Campaign caps required per approval"} tone="purple" />
    </section>
    {dashboard.sandboxMode && experiment
      ? <section className="approval-panel empty-approval"><div><span className="approval-pill"><ShieldCheck size={15} /> External action locked</span><h2>This proposal cannot run in Sandbox.</h2><p>It would use {experiment.channel}. Sandbox mode blocks provider publication, audience resolution, and spend. Run a test experiment above to check the workflow safely.</p></div><ShieldCheck size={28} /></section>
      : experiment
      ? <ApprovalPanel experiment={experiment} audienceName={dashboard.audiences.find((item) => item.id === experiment.audienceId)?.name} busy={busy} onApprove={onApprove} onReject={onReject} />
      : <section className="approval-panel empty-approval"><div><span className="approval-pill"><ShieldCheck size={15} /> Approval queue clear</span><h2>No external action is waiting.</h2><p>Completed and live experiments remain in the pipeline and learning cards. Generate a plan when you are ready for the next bounded proposal.</p></div><ShieldCheck size={28} /></section>}
    <section className="section-grid">
      <div className="section-panel"><div className="section-heading"><div><span className="eyebrow">Active work</span><h3>Experiment pipeline</h3></div><button className="text-button" onClick={onViewExperiments}>View all <ChevronRight size={15} /></button></div><Pipeline experiments={dashboard.experiments} /></div>
      <div className="section-panel learning-snapshot"><div className="section-heading"><div><span className="eyebrow">Learning loop</span><h3>Evidence, not activity</h3></div><ShieldCheck size={19} /></div>{dashboard.learningCards.map((card) => { const item = dashboard.experiments.find((experiment) => experiment.id === card.experimentId); return <article className="learning-item" key={card.id}><div className="learning-icon"><Sparkles size={17} /></div><div><strong>{item?.title ?? "Experiment"}</strong><p>{card.evidence[0]?.detail}</p><span>{card.nextAction}</span></div></article>; })}</div>
    </section>
  </div>;
}

function ApprovalPanel({ experiment, audienceName, busy, onApprove, onReject }: { experiment: Experiment; audienceName?: string; busy?: string; onApprove: (experiment: Experiment) => void; onReject: (experiment: Experiment) => void }) {
  const approving = busy === `approve-${experiment.id}`;
  return <section className="approval-panel">
    <div className="approval-topline"><span className="approval-pill"><Slack size={15} /> Slack decision ready</span><span className={`status-badge status-${experiment.status}`}>{statusLabel[experiment.status]}</span></div>
    <div className="approval-main"><div className="approval-copy"><span className="eyebrow">Best next experiment</span><h2>{experiment.title}</h2><p>{experiment.hypothesis}</p><div className="reason-box"><Bot size={17} /><span><strong>Why this channel:</strong> {experiment.channelRationale}</span></div></div><div className="confidence-box"><span>Expected impact</span><strong>{experiment.expectedImpact}</strong><div className="confidence-track"><i style={{ width: `${experiment.confidence * 100}%` }} /></div><small>{Math.round(experiment.confidence * 100)}% confidence</small></div></div>
    <div className="approval-details"><Detail icon={<UsersRound size={16} />} label="Audience" value={audienceName ?? "No audience selected"} /><Detail icon={<Target size={16} />} label="Success rule" value={experiment.successRule} /><Detail icon={<Clock3 size={16} />} label="Decision window" value={`${experiment.decisionWindowDays} days`} /><Detail icon={<BarChart3 size={16} />} label="Spend controls" value={experiment.surface === "paid" ? `${formatCents(experiment.spend.dailyCents)} daily / ${formatCents(experiment.spend.totalCents)} total` : "No paid spend"} /></div>
    <div className="approval-footer"><span><ShieldCheck size={16} /> The exact creative, audience, metric, and caps are frozen when approved.</span><div><button className="secondary-button danger" onClick={() => onReject(experiment)} disabled={Boolean(busy)}><X size={17} /> Reject</button><button className="primary-button" onClick={() => onApprove(experiment)} disabled={Boolean(busy) || experiment.status !== "awaiting_approval"}>{approving ? <LoaderCircle className="spin" size={17} /> : <Send size={17} />} Approve &amp; queue</button></div></div>
  </section>;
}

function ChannelsView({ dashboard, onOpenExperiment }: { dashboard: DashboardPayload; onOpenExperiment: (experimentId: string) => void }) {
  const sourceLabels = { posthog: "Product analytics", channel: "Provider reporting", workspace: "Workspace records", public_web: "Public research" } as const;
  const sourceDescriptions = { posthog: "Aggregate funnels, events, and cohorts", channel: "Delivery, campaign, and channel metrics", workspace: "User decisions, AI plans, and Sandbox records", public_web: "Cited external market research" } as const;
  const cardsByExperiment = new Map(dashboard.learningCards.map((card) => [card.experimentId, card]));
  const channelIds = [...new Set(dashboard.experiments.map((experiment) => experiment.channel))];
  const allEvidence = dashboard.learningCards.flatMap((card) => card.evidence);
  const verifiedOutcomes = dashboard.learningCards.filter((card) => card.outcome !== "pending" && card.evidence.some((evidence) => evidence.source === "posthog" || evidence.source === "channel"));
  const sandboxOutcomes = dashboard.learningCards.filter((card) => dashboard.experiments.find((experiment) => experiment.id === card.experimentId)?.channel === "sandbox" && card.outcome !== "pending");

  return <div className="view-stack"><section className="page-intro"><div><span className="eyebrow">Channel intelligence</span><h2>See which channels earn confidence.</h2><p>Performance is only verified when a completed experiment has product-analytics or provider evidence. Planning records and Sandbox results are visible, but never counted as channel success.</p></div></section><section className="channel-summary-grid"><article><span>Verified outcomes</span><strong>{verifiedOutcomes.length}</strong><small>completed experiments backed by PostHog or provider data</small></article><article><span>Verified wins</span><strong>{verifiedOutcomes.filter((card) => card.outcome === "win").length}</strong><small>no inferred wins from proposals or simulations</small></article><article><span>Awaiting data</span><strong>{dashboard.learningCards.filter((card) => card.outcome === "pending").length}</strong><small>experiments have not yet produced an outcome</small></article><article><span>Sandbox outcomes</span><strong>{sandboxOutcomes.length}</strong><small>workflow checks, excluded from channel performance</small></article></section><section className="channel-performance" aria-label="Channel performance">{channelIds.map((channel) => { const experiments = dashboard.experiments.filter((experiment) => experiment.channel === channel); const cards = experiments.map((experiment) => cardsByExperiment.get(experiment.id)).filter((card): card is NonNullable<typeof card> => Boolean(card)); const measured = cards.filter((card) => card.outcome !== "pending" && card.evidence.some((evidence) => evidence.source === "posthog" || evidence.source === "channel")); const wins = measured.filter((card) => card.outcome === "win"); const sources = [...new Set(cards.flatMap((card) => card.evidence.map((evidence) => evidence.source)))]; const latestEvidence = cards.flatMap((card) => card.evidence).sort((a, b) => b.capturedAt.localeCompare(a.capturedAt))[0]; const connection = dashboard.connections.find((item) => item.provider === channel); const isSandbox = channel === "sandbox"; const result = measured.length ? `${wins.length}/${measured.length} verified win${measured.length === 1 ? "" : "s"}` : isSandbox && cards.some((card) => card.outcome !== "pending") ? "Simulation only" : "No verified result yet"; return <article className="channel-performance-card" key={channel}><div className="channel-card-header"><ChannelMark channel={channel} /><div><span className="eyebrow">{channel.replaceAll("_", " ")}</span><h3>{connection?.label ?? channel.replaceAll("_", " ")}</h3></div><span className={`connection-state ${connection?.status === "connected" ? "connected" : ""}`}>{isSandbox ? "Local" : connection?.status === "connected" ? "Connected" : "Access required"}</span></div><div className={`channel-result ${measured.length ? "verified" : isSandbox ? "simulated" : "pending"}`}><strong>{result}</strong><span>{measured.length ? "Uses measured product or provider evidence" : isSandbox ? "Excluded from production performance" : "No channel success claim yet"}</span></div><div className="channel-source-row"><span>Data inputs</span><strong>{sources.length ? sources.map((source) => sourceLabels[source]).join(" · ") : "No measurement snapshot yet"}</strong></div><div className="channel-source-row"><span>Latest input</span><strong>{latestEvidence ? dateLabel(latestEvidence.capturedAt) : connection?.lastSyncedAt ? dateLabel(connection.lastSyncedAt) : "Not synced"}</strong></div><div className="channel-source-row"><span>Experiments</span><strong>{experiments.length} attached</strong></div>{experiments[0] && <button className="text-button channel-inspect" onClick={() => onOpenExperiment(experiments[0].id)}>Inspect latest experiment <ChevronRight size={15} /></button>}</article>; })}</section><section className="source-overview"><div className="section-heading"><div><span className="eyebrow">Data lineage</span><h3>Where this view gets its facts</h3></div></div><div className="source-grid">{(Object.keys(sourceLabels) as Array<keyof typeof sourceLabels>).map((source) => { const evidence = allEvidence.filter((item) => item.source === source); const latest = evidence.sort((a, b) => b.capturedAt.localeCompare(a.capturedAt))[0]; const verified = source === "posthog" || source === "channel"; return <article className="source-card" key={source}><span className={`source-icon ${verified ? "verified" : "context"}`}>{verified ? <ShieldCheck size={16} /> : <Layers3 size={16} />}</span><div><strong>{sourceLabels[source]}</strong><p>{sourceDescriptions[source]}</p><small>{evidence.length} evidence record{evidence.length === 1 ? "" : "s"} · {latest ? `last captured ${dateLabel(latest.capturedAt)}` : "not captured yet"}</small></div></article>; })}</div><p className="lineage-note"><ShieldCheck size={15} />Only product analytics and provider reporting can verify channel performance. Workspace and public research records explain decisions, but never prove a win.</p></section></div>;
}

function MetricsView({ dashboard, selectedMetricId, onCloseMetric, onOpenMetric, onOpenExperiment }: { dashboard: DashboardPayload; selectedMetricId?: string; onCloseMetric: () => void; onOpenMetric: (metricId: string) => void; onOpenExperiment: (experimentId: string) => void }) {
  const selectedMetric = dashboard.metricDefinitions.find((metric) => metric.id === selectedMetricId);
  if (selectedMetric) return <MetricDetailView metric={selectedMetric} dashboard={dashboard} onBack={onCloseMetric} onOpenExperiment={onOpenExperiment} />;
  const observedSources = dashboard.dataSources.filter((source) => source.trustLevel === "observed");
  const dataState = dashboard.sandboxMode ? "Sandbox measurements only" : observedSources.length ? `${observedSources.length} observed source${observedSources.length === 1 ? "" : "s"}` : "No observed measurement source";
  const dataDetail = dashboard.sandboxMode
    ? "Any value shown is explicitly simulated. It cannot move a production goal or verify a channel outcome."
    : observedSources.length
      ? "Only verified, observed snapshots count as live goal progress."
      : "Connect and validate a source before treating a metric as live.";
  return <div className="view-stack">
    <section className="page-intro"><div><span className="eyebrow">Metric control</span><h2>Start with the number you intend to move.</h2><p>Every goal uses a registered metric. Current values always show their source, trust level, quality, and capture time.</p></div></section>
    <section className="data-state"><div><Activity size={20} /><div><strong>{dataState}</strong><span>{dataDetail}</span></div></div><span>{dashboard.metricDefinitions.length} registered metric{dashboard.metricDefinitions.length === 1 ? "" : "s"}</span></section>
    <section className="metric-focus-grid">{dashboard.goals.map((goal) => {
      const experiments = dashboard.experiments.filter((experiment) => experiment.goalId === goal.id);
      const activeWork = experiments.filter((experiment) => ["awaiting_approval", "approved", "queued", "live", "measuring"].includes(experiment.status));
      const measurement = measurementForGoal(dashboard, goal);
      const current = measurement.snapshot?.value;
      return <article className="metric-focus-card" key={goal.id}>
        <div className="metric-focus-header"><div><span className="eyebrow">{goal.status === "active" ? "Active focus" : goal.status}</span><h3>{goal.title}</h3></div><span className="metric-kind">{measurement.definition?.status ?? "unregistered"}</span></div>
        <div className="focus-metric"><span>Metric definition</span><strong>{goal.metricName}</strong><small>{measurement.definition?.calculation ?? "No calculation has been registered."}</small></div>
        <div className="focus-values focus-values-three"><div><span>Baseline</span><strong>{formatMetricValue(goal.baseline, goal.unit)}</strong><small>planning input</small></div><div><span>Current</span><strong>{formatMetricValue(current, goal.unit)}</strong><small>{measurement.snapshot ? `${trustLabels[measurement.snapshot.trustLevel]} · ${qualityLabels[measurement.snapshot.quality]}` : "No snapshot"}</small></div><div><span>Target</span><strong>{formatMetricValue(goal.target, goal.unit)}</strong><small>by {new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(new Date(goal.deadline))}</small></div></div>
        <p className="measurement-note"><Activity size={14} />{measurement.snapshot ? `${measurement.source?.label ?? measurement.snapshot.sourceProvider} · ${measurement.source ? freshnessLabels[measurement.source.freshness] : "Source not registered"} · captured ${dateLabel(measurement.snapshot.capturedAt)}` : "Connect or run a source before the current value can be measured."}</p>
        <div className="focus-meta"><span><ShieldCheck size={14} />{goal.guardrail ?? "No guardrail set"}</span><span><FlaskConical size={14} />{activeWork.length} active experiment{activeWork.length === 1 ? "" : "s"}</span></div>
        {measurement.definition && <button className="text-button metric-detail-link" onClick={() => onOpenMetric(measurement.definition!.id)}>View metric history <ChevronRight size={15} /></button>}
        <div className="metric-work"><div className="metric-work-heading"><span>What is intended to move this metric</span><strong>{experiments.length} experiment{experiments.length === 1 ? "" : "s"}</strong></div>{experiments.length ? experiments.slice(0, 4).map((experiment) => <button className="metric-work-row" key={experiment.id} onClick={() => onOpenExperiment(experiment.id)}><ChannelMark channel={experiment.channel} /><span><strong>{experiment.title}</strong><small>{experiment.successRule}</small></span><span className={`status-badge status-${experiment.status}`}>{statusLabel[experiment.status]}</span><ChevronRight size={15} /></button>) : <p className="empty-metric-work">No experiment is attached yet. Create one from the Experiments view.</p>}</div>
      </article>;
    })}</section>
  </div>;
}

function DataView({ dashboard, onCreateMetric, onOpenMetric }: { dashboard: DashboardPayload; onCreateMetric: () => void; onOpenMetric: (metricId: string) => void }) {
  const goalsByMetric = new Map(dashboard.goals.map((goal) => [goal.metricDefinitionId, goal]));
  return <div className="view-stack">
    <section className="page-intro"><div><span className="eyebrow">Data contracts</span><h2>Manage the facts behind every decision.</h2><p>Definitions state how a metric is calculated. Sources state where values come from. Snapshots keep the evidence that was available at the time of a decision.</p></div><div className="page-actions"><button className="primary-button" onClick={onCreateMetric}><Plus size={17} />New metric</button></div></section>
    <section className="source-overview"><div className="section-heading"><div><span className="eyebrow">Source health</span><h3>What can supply a measurement</h3></div></div><div className="source-grid">{dashboard.dataSources.map((source) => <article className="source-card source-health-card" key={source.id}><span className={`source-icon ${source.trustLevel === "observed" ? "verified" : "context"}`}>{source.trustLevel === "observed" ? <ShieldCheck size={16} /> : <Activity size={16} />}</span><div><div className="source-card-title"><strong>{source.label}</strong><span className={`trust-badge trust-${source.trustLevel}`}>{trustLabels[source.trustLevel]}</span></div><p>{source.scope}</p><small>{freshnessLabels[source.freshness]} · {source.lastSyncedAt ? `last sync ${dateLabel(source.lastSyncedAt)}` : "no completed sync"}</small>{source.syncError && <p className="source-error"><CircleAlert size={13} />{source.syncError}</p>}<p className="source-detail">{source.detail}</p></div></article>)}</div></section>
    <section className="metric-registry"><div className="section-heading"><div><span className="eyebrow">Metric registry</span><h3>Definitions before decisions</h3></div><span className="registry-count">{dashboard.metricDefinitions.length} total</span></div><div className="metric-registry-list">{dashboard.metricDefinitions.map((metric) => { const latest = latestSnapshot(dashboard.metricSnapshots, metric.id); const goal = goalsByMetric.get(metric.id); const source = dashboard.dataSources.find((item) => item.provider === metric.sourceProvider); return <article className="metric-registry-row" key={metric.id}><div><span className="metric-kind">v{metric.version} · {metric.kind}</span><h3>{metric.name}</h3><p>{metric.description}</p><button className="text-button metric-detail-link" onClick={() => onOpenMetric(metric.id)}>Inspect metric <ChevronRight size={15} /></button></div><div className="registry-fact"><span>Source</span><strong>{source?.label ?? metric.sourceProvider}</strong><small>{trustLabels[metric.trustLevel]} · {metric.status.replaceAll("_", " ")}</small></div><div className="registry-fact"><span>Definition</span><strong>{metric.calculation}</strong><small>{metric.dimensions.length ? metric.dimensions.join(" · ") : "No dimensions"}</small></div><div className="registry-fact"><span>Latest value</span><strong>{formatMetricValue(latest?.value, metric.unit)}</strong><small>{latest ? `${trustLabels[latest.trustLevel]} · ${qualityLabels[latest.quality]}` : "No snapshot"}</small></div><div className="registry-fact"><span>Used by</span><strong>{goal?.title ?? "No goal"}</strong><small>{goal ? "Goal mapping active" : "Create a goal to activate"}</small></div></article>; })}</div></section>
  </div>;
}

function MetricDetailView({ metric, dashboard, onBack, onOpenExperiment }: { metric: MetricDefinition; dashboard: DashboardPayload; onBack: () => void; onOpenExperiment: (experimentId: string) => void }) {
  const snapshots = dashboard.metricSnapshots.filter((snapshot) => snapshot.metricDefinitionId === metric.id).sort((left, right) => left.capturedAt.localeCompare(right.capturedAt));
  const latest = snapshots[snapshots.length - 1];
  const first = snapshots[0];
  const source = dashboard.dataSources.find((item) => item.provider === metric.sourceProvider);
  const linkedGoals = dashboard.goals.filter((goal) => goal.metricDefinitionId === metric.id);
  const linkedExperiments = dashboard.experiments.filter((experiment) => linkedGoals.some((goal) => goal.id === experiment.goalId));
  const change = first && latest && first.id !== latest.id ? latest.value - first.value : undefined;
  return <div className="view-stack metric-detail-view">
    <section className="page-intro metric-detail-intro"><div><button className="text-button back-button" onClick={onBack}><ChevronRight size={15} />All metrics</button><span className="eyebrow">Metric record · v{metric.version}</span><h2>{metric.name}</h2><p>{metric.description}</p></div><div className="metric-record-state"><span className={`trust-badge trust-${metric.trustLevel}`}>{trustLabels[metric.trustLevel]}</span><strong>{metric.status.replaceAll("_", " ")}</strong><small>{source?.label ?? metric.sourceProvider} · {source ? freshnessLabels[source.freshness] : "source unavailable"}</small></div></section>
    <section className="metric-detail-summary"><article><span>Current</span><strong>{formatMetricValue(latest?.value, metric.unit)}</strong><small>{latest ? `${qualityLabels[latest.quality]} · ${dateLabel(latest.capturedAt)}` : "No captured aggregate"}</small></article><article><span>Change in history</span><strong>{change === undefined ? "Not enough data" : `${change >= 0 ? "+" : ""}${formatMetricValue(change, metric.unit)}`}</strong><small>{snapshots.length} snapshot{snapshots.length === 1 ? "" : "s"} retained</small></article><article><span>Refresh cadence</span><strong>{metric.cadence}</strong><small>{metric.lastSyncedAt ? `Metric synced ${dateLabel(metric.lastSyncedAt)}` : "No completed metric sync"}</small></article></section>
    <section className="trend-panel"><div className="section-heading"><div><span className="eyebrow">Aggregate history</span><h3>What this metric has actually recorded</h3></div><span className="registry-count">{snapshots.length ? `${dateLabel(snapshots[0].capturedAt)} to ${dateLabel(snapshots[snapshots.length - 1].capturedAt)}` : "Awaiting first snapshot"}</span></div>{snapshots.length ? <MetricTrend snapshots={snapshots} unit={metric.unit} /> : <div className="metric-empty-state"><Activity size={20} /><div><strong>No snapshot yet</strong><p>{metric.sourceProvider === "posthog" && !metric.sourceMetricId ? "Map this metric to a saved PostHog insight, then refresh measurements." : metric.sourceProvider === "sandbox" ? "Run a sandbox experiment mapped to this metric to record a simulated result." : "The connected source has not returned an aggregate value for this metric yet."}</p></div></div>}</section>
    <section className="section-grid metric-record-grid"><div className="section-panel"><div className="section-heading"><div><span className="eyebrow">Measurement contract</span><h3>How the number is defined</h3></div></div><div className="metric-contract"><Detail icon={<Layers3 size={15} />} label="Calculation" value={metric.calculation} /><Detail icon={<Activity size={15} />} label="Source" value={source?.label ?? metric.sourceProvider} /><Detail icon={<Radio size={15} />} label="Source mapping" value={metric.sourceMetricId ? `Saved PostHog insight #${metric.sourceMetricId}` : "No source record mapped"} /><Detail icon={<Settings2 size={15} />} label="Dimensions" value={metric.dimensions.length ? metric.dimensions.join(", ") : "No dimensions"} /></div><p className="measurement-note"><ShieldCheck size={14} />The monitor reads aggregate insight output only. It does not retrieve people, raw events, or personal properties.</p></div><div className="section-panel"><div className="section-heading"><div><span className="eyebrow">Linked work</span><h3>What is meant to move it</h3></div></div>{linkedGoals.length ? <div className="linked-goals">{linkedGoals.map((goal) => <div key={goal.id}><span>Goal</span><strong>{goal.title}</strong><small>{formatMetricValue(goal.baseline, goal.unit)} baseline · {formatMetricValue(goal.target, goal.unit)} target</small></div>)}</div> : <p className="empty-metric-work">No goal uses this metric yet.</p>}{linkedExperiments.length ? <div className="metric-work">{linkedExperiments.map((experiment) => <button className="metric-work-row" key={experiment.id} onClick={() => onOpenExperiment(experiment.id)}><ChannelMark channel={experiment.channel} /><span><strong>{experiment.title}</strong><small>{experiment.successRule}</small></span><span className={`status-badge status-${experiment.status}`}>{statusLabel[experiment.status]}</span><ChevronRight size={15} /></button>)}</div> : <p className="empty-metric-work">No experiment is linked to this metric.</p>}</div></section>
    {snapshots.length > 0 && <section className="metric-snapshot-table"><div className="section-heading"><div><span className="eyebrow">Snapshot log</span><h3>Evidence retained for decisions</h3></div></div><div className="snapshot-table-head"><span>Captured</span><span>Value</span><span>Trust</span><span>Series</span></div>{snapshots.slice(-8).reverse().map((snapshot) => <div className="snapshot-table-row" key={snapshot.id}><span>{dateLabel(snapshot.capturedAt)}</span><strong>{formatMetricValue(snapshot.value, metric.unit)}</strong><span><i className={`trust-badge trust-${snapshot.trustLevel}`}>{trustLabels[snapshot.trustLevel]}</i> · {qualityLabels[snapshot.quality]}</span><span>{typeof snapshot.dimensions.series === "string" ? snapshot.dimensions.series : "Aggregate"}</span></div>)}</section>}
  </div>;
}

function MetricTrend({ snapshots, unit }: { snapshots: MetricSnapshot[]; unit: string }) {
  const width = 680;
  const height = 184;
  const padding = { top: 16, right: 12, bottom: 28, left: 42 };
  const values = snapshots.map((snapshot) => snapshot.value);
  const lowest = Math.min(...values);
  const highest = Math.max(...values);
  const span = highest - lowest || Math.max(Math.abs(highest) * 0.1, 1);
  const points = snapshots.map((snapshot, index) => {
    const x = snapshots.length === 1 ? width / 2 : padding.left + (index / (snapshots.length - 1)) * (width - padding.left - padding.right);
    const y = padding.top + (1 - (snapshot.value - lowest) / span) * (height - padding.top - padding.bottom);
    return { x, y, snapshot };
  });
  const polyline = points.map((point) => `${point.x},${point.y}`).join(" ");
  return <div className="metric-trend"><div className="trend-legend"><span>{formatMetricValue(highest, unit)}</span><span>{formatMetricValue(lowest, unit)}</span></div><svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${snapshots.length} aggregate metric snapshots over time`} preserveAspectRatio="none"><line x1={padding.left} y1={padding.top} x2={width - padding.right} y2={padding.top} /><line x1={padding.left} y1={height - padding.bottom} x2={width - padding.right} y2={height - padding.bottom} />{points.length > 1 ? <polyline points={polyline} /> : null}{points.map((point) => <circle key={point.snapshot.id} cx={point.x} cy={point.y} r="4" />)}<text x={padding.left} y={height - 7}>{new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(new Date(points[0].snapshot.capturedAt))}</text><text x={width - padding.right} y={height - 7} textAnchor="end">{new Intl.DateTimeFormat("en", { month: "short", day: "numeric" }).format(new Date(points[points.length - 1].snapshot.capturedAt))}</text></svg></div>;
}

function ExperimentsView({ dashboard, busy, selectedExperimentId, onSelect, onCreate, onEdit, onApprove, onReject, onOpenConnections }: { dashboard: DashboardPayload; busy?: string; selectedExperimentId?: string; onSelect: (experimentId: string) => void; onCreate: () => void; onEdit: (experiment: Experiment) => void; onApprove: (experiment: Experiment) => void; onReject: (experiment: Experiment) => void; onOpenConnections: () => void }) {
  const selected = dashboard.experiments.find((experiment) => experiment.id === selectedExperimentId) ?? dashboard.experiments[0];
  return <div className="view-stack"><section className="page-intro"><div><span className="eyebrow">Experiment control</span><h2>Inspect the plan. Steer the decision.</h2><p>Open an experiment to see exactly what AI proposed, the data behind it, the success rule, and the decision you can make.</p></div><div className="page-actions"><div className="legend"><span><i className="legend-dot awaiting" />Needs approval</span><span><i className="legend-dot live" />Live</span><span><i className="legend-dot blocked" />Blocked</span></div><button className="primary-button" onClick={onCreate}><Plus size={17} />New experiment</button></div></section><section className="experiment-workbench"><div className="experiment-list" aria-label="Experiments">{dashboard.experiments.map((experiment) => <article className={`experiment-row ${selected?.id === experiment.id ? "is-selected" : ""}`} key={experiment.id}><div className="experiment-channel"><ChannelMark channel={experiment.channel} /></div><div className="experiment-main"><div className="row-title"><h3>{experiment.title}</h3><span className={`status-badge status-${experiment.status}`}>{statusLabel[experiment.status]}</span></div><p>{experiment.hypothesis}</p><div className="row-meta"><span><Target size={14} />{experiment.optimizationMetric}</span><span><Clock3 size={14} />{experiment.decisionWindowDays} days</span><span><BarChart3 size={14} />{experiment.expectedImpact} impact</span></div></div><button className="text-button inspect-button" onClick={() => onSelect(experiment.id)} aria-current={selected?.id === experiment.id ? "true" : undefined}><Eye size={15} />{selected?.id === experiment.id ? "Viewing" : "Inspect"}</button></article>)}</div>{selected && <ExperimentDetail experiment={selected} dashboard={dashboard} busy={busy} onEdit={onEdit} onApprove={onApprove} onReject={onReject} onOpenConnections={onOpenConnections} />}</section></div>;
}

function ExperimentDetail({ experiment, dashboard, busy, onEdit, onApprove, onReject, onOpenConnections }: { experiment: Experiment; dashboard: DashboardPayload; busy?: string; onEdit: (experiment: Experiment) => void; onApprove: (experiment: Experiment) => void; onReject: (experiment: Experiment) => void; onOpenConnections: () => void }) {
  const goal = dashboard.goals.find((item) => item.id === experiment.goalId);
  const audience = dashboard.audiences.find((item) => item.id === experiment.audienceId);
  const learning = dashboard.learningCards.find((item) => item.experimentId === experiment.id);
  const brief = dashboard.engineeringBriefs.find((item) => item.experimentId === experiment.id);
  const isExternal = experiment.channel !== "sandbox" && experiment.channel !== "posthog";
  const canEdit = ["proposed", "needs_changes", "awaiting_approval", "blocked"].includes(experiment.status);
  const outcomeLabel = learning ? learning.outcome === "pending" ? "Outcome not measured yet" : `Outcome: ${learning.outcome}` : "No learning card yet";
  const editButton = canEdit ? <button className="secondary-button" onClick={() => onEdit(experiment)}><Settings2 size={16} />Edit proposal</button> : null;

  return <aside className="experiment-detail" aria-label="Experiment decision record">
    <div className="detail-header"><div><span className="eyebrow">Decision record</span><h2>{experiment.title}</h2></div><span className={`status-badge status-${experiment.status}`}>{statusLabel[experiment.status]}</span></div>
    <p className="detail-summary">{experiment.hypothesis}</p>
    <section className="detail-section"><span className="detail-label">Why AI selected this</span><p>{experiment.channelRationale}</p></section>
    <section className="detail-section detail-facts"><Detail icon={<Target size={15} />} label="Goal metric" value={goal ? `${goal.metricName}: ${goal.baseline}${goal.unit} to ${goal.target}${goal.unit}` : experiment.optimizationMetric} /><Detail icon={<UsersRound size={15} />} label="Audience" value={audience ? `${audience.name} (${audience.estimatedPeople.toLocaleString()} eligible)` : "No audience selected"} /><Detail icon={<Clock3 size={15} />} label="Decision window" value={`${experiment.decisionWindowDays} days`} /><Detail icon={<BarChart3 size={15} />} label="Spend impact" value={experiment.surface === "paid" ? `${formatCents(experiment.spend.dailyCents)} daily / ${formatCents(experiment.spend.totalCents)} total` : "No paid spend"} /></section>
    <section className="detail-section"><span className="detail-label">How success is measured</span><strong className="success-rule">{experiment.successRule}</strong><p className="measurement-state"><Activity size={15} />{outcomeLabel}{learning?.evaluatedAt ? ` on ${dateLabel(learning.evaluatedAt)}` : ""}</p>{learning && <div className="evidence-list detail-evidence">{learning.evidence.map((evidence) => <div key={evidence.id}><span className="evidence-source">{evidence.source.replace("_", " ")}</span><strong>{evidence.label}</strong><p>{evidence.detail}</p></div>)}</div>}</section>
    <section className="detail-section"><span className="detail-label">What would run</span><div className="variant-list">{experiment.variants.map((variant) => <div className="variant-detail" key={variant.id}><strong>{variant.name}</strong><span>{variant.headline}</span><p>{variant.body}</p><a href={variant.trackingUrl} target="_blank" rel="noreferrer">Open tracking destination <ArrowUpRight size={13} /></a></div>)}</div></section>
    {brief && <section className="detail-section engineering-note"><span className="detail-label">Engineering gate</span><strong>Feature flag: {brief.flagKey}</strong><p>{experiment.engineeringBrief}</p><ul>{brief.trackingRequirements.map((requirement) => <li key={requirement}>{requirement}</li>)}</ul></section>}
    <section className="detail-section steering-panel"><span className="detail-label">Your control</span>{dashboard.sandboxMode && isExternal ? <><strong>External execution is locked for this test workspace.</strong><p>You can revise this proposal, but Sandbox will not publish, resolve people, or spend money.</p>{editButton}</> : experiment.status === "awaiting_approval" ? <><strong>Decide whether this exact plan should run.</strong><p>Approval freezes the audience, copy, metric, schedule, and any spend caps. Rejecting stops it before publication.</p><div className="detail-actions">{editButton}<button className="secondary-button danger" onClick={() => onReject(experiment)} disabled={Boolean(busy)}><X size={16} />Reject</button><button className="primary-button" onClick={() => onApprove(experiment)} disabled={Boolean(busy)}><Send size={16} />Approve &amp; queue</button></div></> : experiment.status === "blocked" ? <><strong>This experiment cannot run until the channel is authorized.</strong><p>Nothing will be published until the required provider access is connected.</p><div className="detail-actions">{editButton}<button className="secondary-button" onClick={onOpenConnections}><Link2 size={16} />Review connections</button></div></> : experiment.status === "awaiting_engineering" ? <><strong>This product test is waiting for the tracking contract above.</strong><p>Once engineering registers the flag and events, an admin can review the exact launch plan.</p></> : <><strong>{learning?.nextAction ?? "This experiment is being monitored."}</strong><p>Its result and evidence stay attached to this decision record so the next experiment can build on it.</p></>}</section>
  </aside>;
}

function LearningView({ dashboard, onOpenExperiment }: { dashboard: DashboardPayload; onOpenExperiment: (experimentId: string) => void }) {
  return <div className="view-stack"><section className="page-intro"><div><span className="eyebrow">Institutional memory</span><h2>Learn once. Compound the result.</h2><p>Every experiment retains the evidence, outcome, and recommendation that led to the next decision.</p></div></section><section className="learning-grid">{dashboard.learningCards.map((card) => { const experiment = dashboard.experiments.find((item) => item.id === card.experimentId); return <article className="learning-card" key={card.id}><div className="card-top"><span className="eyebrow">{card.outcome === "pending" ? "In progress" : card.outcome}</span><span>{Math.round(card.confidence * 100)}% confidence</span></div><h3>{experiment?.title ?? "Experiment"}</h3><p>{card.outcomeSummary}</p><div className="evidence-list">{card.evidence.map((evidence) => <div key={evidence.id}><span className="evidence-source">{evidence.source.replace("_", " ")}</span><strong>{evidence.label}</strong><p>{evidence.detail}</p></div>)}</div><footer><Sparkles size={16} />{card.nextAction}</footer>{experiment && <button className="text-button learning-open" onClick={() => onOpenExperiment(experiment.id)}>Inspect experiment <ChevronRight size={15} /></button>}</article>; })}</section></div>;
}

function ConnectionsView({ connections, sandboxMode, onSetupPostHog }: { connections: ProviderConnection[]; sandboxMode: boolean; onSetupPostHog: () => void }) {
  const connected = connections.filter((connection) => connection.status === "connected");
  const awaiting = connections.filter((connection) => connection.status !== "connected");
  return <div className="view-stack"><section className="page-intro"><div><span className="eyebrow">Integration control plane</span><h2>AI chooses only from authorized capabilities.</h2><p>A platform never receives an external write until its account, scopes, and app review are fully connected.</p></div><div className="connection-summary"><strong>{connected.length}</strong><span>connected</span></div></section><section className="connection-section"><div className="section-heading"><div><span className="eyebrow">Ready now</span><h3>Authorized connections</h3></div></div><ConnectionGrid connections={connected} sandboxMode={sandboxMode} onSetupPostHog={onSetupPostHog} /></section><section className="connection-section"><div className="section-heading"><div><span className="eyebrow">Access required</span><h3>Channel registry</h3></div></div><ConnectionGrid connections={awaiting} sandboxMode={sandboxMode} onSetupPostHog={onSetupPostHog} /></section></div>;
}

function ConnectionGrid({ connections, sandboxMode, onSetupPostHog }: { connections: ProviderConnection[]; sandboxMode: boolean; onSetupPostHog: () => void }) { return <div className="connection-grid">{connections.map((connection) => <article className="connection-card" key={connection.id}><div className="connection-card-top"><ChannelMark channel={connection.provider} /><span className={`connection-state ${connection.status}`}>{connection.provider === "sandbox" ? "No connection" : connection.status === "connected" ? "Connected" : "Access required"}</span></div><h3>{connection.label}</h3><p>{connection.detail}</p>{connection.syncError && <p className="connection-error"><CircleAlert size={13} />{connection.syncError}</p>}<div className="capability-list">{connection.capabilities.length ? connection.capabilities.map((capability) => <span key={capability}>{capability.replaceAll("_", " ")}</span>) : <span>OAuth and provider access required</span>}</div>{connection.provider === "posthog" && <button className="secondary-button connection-action" onClick={onSetupPostHog} disabled={sandboxMode} title={sandboxMode ? "Live provider reads are locked in Sandbox mode" : undefined}><Activity size={16} />{connection.status === "connected" ? "Re-verify PostHog" : "Connect PostHog"}</button>}{connection.provider === "posthog" && sandboxMode && <small className="connection-lock">Live analytics stays locked in Sandbox.</small>}</article>)}</div>; }

const channelsForSurface: Record<Experiment["surface"], Experiment["channel"][]> = {
  email: ["resend"],
  paid: ["linkedin", "meta", "tiktok", "snapchat", "google_ads", "x", "reddit", "pinterest"],
  organic: ["linkedin", "meta", "tiktok", "x", "reddit", "pinterest"],
  product: ["posthog"]
};

function ExperimentCreateForm({ goals, audiences, onClose, onSubmit }: { goals: Goal[]; audiences: DashboardPayload["audiences"]; onClose: () => void; onSubmit: (experiment: ExperimentCreateInput) => void }) {
  const initialGoal = goals.find((goal) => goal.status === "active") ?? goals[0];
  const [goalId, setGoalId] = useState(initialGoal?.id ?? "");
  const [title, setTitle] = useState("");
  const [surface, setSurface] = useState<Experiment["surface"]>("email");
  const [channel, setChannel] = useState<Experiment["channel"]>("resend");
  const [hypothesis, setHypothesis] = useState("");
  const [rationale, setRationale] = useState("");
  const [impact, setImpact] = useState<Experiment["expectedImpact"]>("medium");
  const [audienceId, setAudienceId] = useState(audiences.find((audience) => audience.eligible)?.id ?? "");
  const [successRule, setSuccessRule] = useState("");
  const [decisionWindowDays, setDecisionWindowDays] = useState("14");
  const [headline, setHeadline] = useState("");
  const [body, setBody] = useState("");
  const [destination, setDestination] = useState("https://product.example.com");
  const [dailyBudget, setDailyBudget] = useState("");
  const [totalBudget, setTotalBudget] = useState("");
  const [startAt, setStartAt] = useState("");
  const [stopAt, setStopAt] = useState("");
  const [flagKey, setFlagKey] = useState("");
  const goal = goals.find((item) => item.id === goalId) ?? initialGoal;
  const isPaid = surface === "paid";
  const toCents = (value: string) => value ? Math.round(Number(value) * 100) : undefined;
  const toIso = (value: string) => value ? new Date(value).toISOString() : undefined;
  const chooseSurface = (next: Experiment["surface"]) => { setSurface(next); setChannel(channelsForSurface[next][0]); };

  return <div className="modal-backdrop" role="presentation"><form className="goal-modal experiment-create-modal" onSubmit={(event) => { event.preventDefault(); if (!goal) return; onSubmit({ goalId: goal.id, title, surface, channel, hypothesis, channelRationale: rationale, expectedImpact: impact, confidence: impact === "high" ? 0.75 : impact === "medium" ? 0.6 : 0.45, audienceId: audienceId || undefined, successRule, decisionWindowDays: Number(decisionWindowDays), variants: [{ id: `variant_${crypto.randomUUID()}`, name: "User proposal", headline, body, assetIds: [], trackingUrl: destination }], spend: { dailyCents: toCents(dailyBudget), totalCents: toCents(totalBudget), startAt: toIso(startAt), stopAt: toIso(stopAt) }, engineeringFlagKey: surface === "product" ? flagKey : undefined }); }}><header><div><span className="eyebrow">Manual experiment</span><h2>Create a plan to move one metric.</h2><p>Creating saves an approval-gated record. It never sends, publishes, or spends.</p></div><button className="icon-button" type="button" onClick={onClose} aria-label="Close"><X size={18} /></button></header><div className="form-grid"><label>Goal<select value={goalId} onChange={(event) => setGoalId(event.target.value)} required>{goals.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}</select></label><label>Metric this will move<input value={goal?.metricName ?? ""} readOnly /></label></div><label>Experiment name<input value={title} onChange={(event) => setTitle(event.target.value)} minLength={8} required /></label><div className="form-grid"><label>Surface<select value={surface} onChange={(event) => chooseSurface(event.target.value as Experiment["surface"])}><option value="email">Email</option><option value="paid">Paid campaign</option><option value="organic">Organic post</option><option value="product">Product experiment</option></select></label><label>Channel<select value={channel} onChange={(event) => setChannel(event.target.value as Experiment["channel"])}>{channelsForSurface[surface].map((item) => <option key={item} value={item}>{item.replaceAll("_", " ")}</option>)}</select></label></div><label>Hypothesis<textarea value={hypothesis} onChange={(event) => setHypothesis(event.target.value)} minLength={20} required /></label><label>Why this channel<textarea value={rationale} onChange={(event) => setRationale(event.target.value)} minLength={20} required /></label><div className="form-grid"><label>Expected impact<select value={impact} onChange={(event) => setImpact(event.target.value as Experiment["expectedImpact"])}><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option></select></label><label>Decision window (days)<input type="number" min="1" max="120" value={decisionWindowDays} onChange={(event) => setDecisionWindowDays(event.target.value)} required /></label></div>{surface === "email" && <label>Audience<select value={audienceId} onChange={(event) => setAudienceId(event.target.value)} required><option value="">Choose a consented audience</option>{audiences.filter((audience) => audience.eligible).map((audience) => <option key={audience.id} value={audience.id}>{audience.name} ({audience.estimatedPeople.toLocaleString()} eligible)</option>)}</select></label>}<label>Success rule<textarea value={successRule} onChange={(event) => setSuccessRule(event.target.value)} minLength={10} required /></label><div className="variant-editor"><span className="detail-label">First creative variant</span><label>Headline<input value={headline} onChange={(event) => setHeadline(event.target.value)} minLength={2} required /></label><label>Body<textarea value={body} onChange={(event) => setBody(event.target.value)} minLength={2} required /></label><label>Tracking destination<input type="url" value={destination} onChange={(event) => setDestination(event.target.value)} required /></label></div>{isPaid && <div className="variant-editor paid-controls"><span className="detail-label">Required paid caps</span><div className="form-grid"><label>Daily cap (EUR)<input type="number" min="1" value={dailyBudget} onChange={(event) => setDailyBudget(event.target.value)} required /></label><label>Total cap (EUR)<input type="number" min="1" value={totalBudget} onChange={(event) => setTotalBudget(event.target.value)} required /></label><label>Start<input type="datetime-local" value={startAt} onChange={(event) => setStartAt(event.target.value)} required /></label><label>Stop<input type="datetime-local" value={stopAt} onChange={(event) => setStopAt(event.target.value)} required /></label></div></div>}{surface === "product" && <label>Feature flag key<input value={flagKey} onChange={(event) => setFlagKey(event.target.value)} pattern="[a-z][a-z0-9_]*" required /></label>}<footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="submit" className="primary-button"><Plus size={17} />Create experiment</button></footer></form></div>;
}

function ExperimentEditForm({ experiment, audiences, onClose, onSubmit }: { experiment: Experiment; audiences: DashboardPayload["audiences"]; onClose: () => void; onSubmit: (update: ExperimentDraftUpdate) => void }) {
  const [hypothesis, setHypothesis] = useState(experiment.hypothesis);
  const [audienceId, setAudienceId] = useState(experiment.audienceId ?? "");
  const [successRule, setSuccessRule] = useState(experiment.successRule);
  const [decisionWindowDays, setDecisionWindowDays] = useState(String(experiment.decisionWindowDays));
  const [dailyBudget, setDailyBudget] = useState(experiment.spend.dailyCents ? String(experiment.spend.dailyCents / 100) : "");
  const [totalBudget, setTotalBudget] = useState(experiment.spend.totalCents ? String(experiment.spend.totalCents / 100) : "");
  const [variants, setVariants] = useState(experiment.variants);
  const updateVariant = (variantId: string, field: "headline" | "body", value: string) => setVariants((current) => current.map((variant) => variant.id === variantId ? { ...variant, [field]: value } : variant));
  const toCents = (value: string) => value ? Math.round(Number(value) * 100) : undefined;

  return <div className="modal-backdrop" role="presentation"><form className="goal-modal experiment-modal" onSubmit={(event) => { event.preventDefault(); onSubmit({ hypothesis, audienceId: audienceId || undefined, successRule, decisionWindowDays: Number(decisionWindowDays), variants, spend: { ...experiment.spend, dailyCents: toCents(dailyBudget), totalCents: toCents(totalBudget) } }); }}><header><div><span className="eyebrow">Human steering</span><h2>Edit the proposal before approval.</h2><p>Saving changes the decision record only. It does not publish, resolve an audience, or spend money.</p></div><button className="icon-button" type="button" onClick={onClose} aria-label="Close"><X size={18} /></button></header><label>Hypothesis<textarea value={hypothesis} onChange={(event) => setHypothesis(event.target.value)} required /></label><label>Audience<select value={audienceId} onChange={(event) => setAudienceId(event.target.value)}><option value="">No audience selected</option>{audiences.map((audience) => <option key={audience.id} value={audience.id}>{audience.name} ({audience.estimatedPeople.toLocaleString()} eligible)</option>)}</select></label><label>Success rule<textarea value={successRule} onChange={(event) => setSuccessRule(event.target.value)} required /></label><div className="form-grid"><label>Decision window (days)<input type="number" min="1" max="120" value={decisionWindowDays} onChange={(event) => setDecisionWindowDays(event.target.value)} required /></label>{experiment.surface === "paid" && <label>Daily cap (EUR)<input type="number" min="1" step="1" value={dailyBudget} onChange={(event) => setDailyBudget(event.target.value)} required /></label>}{experiment.surface === "paid" && <label>Total cap (EUR)<input type="number" min="1" step="1" value={totalBudget} onChange={(event) => setTotalBudget(event.target.value)} required /></label>}</div><div className="variant-editor"><span className="detail-label">Creative variants</span>{variants.map((variant) => <fieldset key={variant.id}><legend>{variant.name}</legend><label>Headline<input value={variant.headline} onChange={(event) => updateVariant(variant.id, "headline", event.target.value)} required /></label><label>Body<textarea value={variant.body} onChange={(event) => updateVariant(variant.id, "body", event.target.value)} required /></label></fieldset>)}</div><footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="submit" className="primary-button"><Check size={17} />Save proposal</button></footer></form></div>;
}

function GoalForm({ metricDefinitions, sandboxMode, onClose, onSubmit }: { metricDefinitions: DashboardPayload["metricDefinitions"]; sandboxMode: boolean; onClose: () => void; onSubmit: (goal: Omit<Goal, "id" | "status">) => void }) {
  const eligibleMetrics = metricDefinitions.filter((metric) => metric.status !== "archived" && (sandboxMode || (metric.status === "ready" && metric.trustLevel === "observed")));
  const [title, setTitle] = useState("Increase activated workspaces");
  const [metricDefinitionId, setMetricDefinitionId] = useState(eligibleMetrics[0]?.id ?? "");
  const [baseline, setBaseline] = useState("31");
  const [target, setTarget] = useState("45");
  const [deadline, setDeadline] = useState("2026-09-30");
  const [budget, setBudget] = useState("3500");
  const selectedMetric = eligibleMetrics.find((metric) => metric.id === metricDefinitionId);
  return <div className="modal-backdrop" role="presentation"><form className="goal-modal" onSubmit={(event) => { event.preventDefault(); if (!selectedMetric) return; onSubmit({ title, metricDefinitionId: selectedMetric.id, metricKind: selectedMetric.kind, metricName: selectedMetric.name, baseline: Number(baseline), target: Number(target), unit: selectedMetric.unit, deadline, guardrail: "Trial-to-paid conversion must remain stable.", monthlyBudgetCents: Number(budget) * 100 }); }}><header><div><span className="eyebrow">New growth outcome</span><h2>Set the result. AI will find the work.</h2><p>A goal uses a registered metric, not a free-text label. Live goals require an observed source.</p></div><button className="icon-button" type="button" onClick={onClose} aria-label="Close"><X size={18} /></button></header><label>Outcome<input value={title} onChange={(event) => setTitle(event.target.value)} required /></label><label>Metric definition<select value={metricDefinitionId} onChange={(event) => setMetricDefinitionId(event.target.value)} required><option value="">Choose a registered metric</option>{eligibleMetrics.map((metric) => <option key={metric.id} value={metric.id}>{metric.name} · {trustLabels[metric.trustLevel]}</option>)}</select></label>{selectedMetric && <div className="form-hint"><ShieldCheck size={15} /><span><strong>{selectedMetric.calculation}</strong><br />{selectedMetric.sourceProvider} · {trustLabels[selectedMetric.trustLevel]} · {selectedMetric.status.replaceAll("_", " ")}</span></div>}<div className="form-grid"><label>Baseline<input type="number" value={baseline} onChange={(event) => setBaseline(event.target.value)} required /></label><label>Target<input type="number" value={target} onChange={(event) => setTarget(event.target.value)} required /></label></div><div className="form-grid"><label>Deadline<input type="date" value={deadline} onChange={(event) => setDeadline(event.target.value)} required /></label><label>Monthly paid budget (EUR)<input type="number" min="0" value={budget} onChange={(event) => setBudget(event.target.value)} required /></label></div><footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="submit" className="primary-button" disabled={!selectedMetric}><Target size={17} />Create goal</button></footer></form></div>;
}

function MetricDefinitionForm({ dataSources, sandboxMode, onClose, onSubmit }: { dataSources: DashboardPayload["dataSources"]; sandboxMode: boolean; onClose: () => void; onSubmit: (metric: MetricDefinitionInput) => void }) {
  const selectableSources = dataSources.filter((source) => source.provider !== "workspace");
  const [name, setName] = useState("Activated workspaces");
  const [description, setDescription] = useState("Share of new workspaces that complete the first shared project activation step.");
  const [kind, setKind] = useState<MetricDefinitionInput["kind"]>("funnel");
  const [sourceProvider, setSourceProvider] = useState<MetricDefinitionInput["sourceProvider"]>(selectableSources[0]?.provider ?? "workspace");
  const [calculation, setCalculation] = useState("Created first shared project / completed signup");
  const [unit, setUnit] = useState("%");
  const [dimensions, setDimensions] = useState("plan, acquisition_channel");
  const [cadence, setCadence] = useState<MetricDefinitionInput["cadence"]>("daily");
  const [sourceMetricId, setSourceMetricId] = useState("");
  const [postHogInsights, setPostHogInsights] = useState<PostHogInsight[]>([]);
  const [postHogDiscoveryError, setPostHogDiscoveryError] = useState<string>();
  const selectedSource = selectableSources.find((source) => source.provider === sourceProvider);
  useEffect(() => {
    if (sourceProvider !== "posthog" || sandboxMode) return;
    let cancelled = false;
    setPostHogDiscoveryError(undefined);
    void api.posthogInsights().then(({ insights }) => { if (!cancelled) setPostHogInsights(insights); }).catch((error) => { if (!cancelled) setPostHogDiscoveryError(error instanceof Error ? error.message : "Could not discover saved PostHog insights."); });
    return () => { cancelled = true; };
  }, [sourceProvider, sandboxMode]);
  return <div className="modal-backdrop" role="presentation"><form className="goal-modal experiment-modal" onSubmit={(event) => { event.preventDefault(); onSubmit({ name, description, kind, sourceProvider, calculation, sourceMetricId: sourceProvider === "posthog" ? sourceMetricId || undefined : undefined, unit, dimensions: dimensions.split(",").map((item) => item.trim()).filter(Boolean), cadence }); }}><header><div><span className="eyebrow">Metric definition</span><h2>Define what the team will measure.</h2><p>Definitions are versioned and visible wherever the metric is used. A source remains unavailable until its connection and read access are validated.</p></div><button className="icon-button" type="button" onClick={onClose} aria-label="Close"><X size={18} /></button></header><label>Name<input value={name} onChange={(event) => setName(event.target.value)} minLength={2} required /></label><label>Description<textarea value={description} onChange={(event) => setDescription(event.target.value)} minLength={10} required /></label><div className="form-grid"><label>Metric type<select value={kind} onChange={(event) => setKind(event.target.value as MetricDefinitionInput["kind"])}><option value="event">Event</option><option value="funnel">Funnel</option><option value="cohort">Cohort</option><option value="custom">Custom</option></select></label><label>Measurement source<select value={sourceProvider} onChange={(event) => setSourceProvider(event.target.value as MetricDefinitionInput["sourceProvider"])}>{selectableSources.map((source) => <option key={source.id} value={source.provider}>{source.label} · {trustLabels[source.trustLevel]}</option>)}</select></label></div>{selectedSource && <div className="form-hint"><Activity size={15} /><span><strong>{selectedSource.scope}</strong><br />{selectedSource.detail}</span></div>}{sourceProvider === "posthog" && <label>Saved PostHog insight<select value={sourceMetricId} onChange={(event) => setSourceMetricId(event.target.value)} required={!sandboxMode && selectedSource?.trustLevel === "observed"}><option value="">{sandboxMode ? "Unavailable in Sandbox" : "Choose the aggregate insight to read"}</option>{postHogInsights.map((insight) => <option key={insight.id} value={insight.id}>{insight.name} · #{insight.id}</option>)}</select>{postHogDiscoveryError && <small className="form-error">{postHogDiscoveryError}</small>}{!sandboxMode && !postHogInsights.length && !postHogDiscoveryError && <small className="form-help">Connect and verify PostHog before saved insights can be selected.</small>}</label>}<label>Calculation or query meaning<textarea value={calculation} onChange={(event) => setCalculation(event.target.value)} minLength={5} required /></label><div className="form-grid"><label>Unit<input value={unit} onChange={(event) => setUnit(event.target.value)} maxLength={24} required /></label><label>Cadence<select value={cadence} onChange={(event) => setCadence(event.target.value as MetricDefinitionInput["cadence"])}><option value="hourly">Hourly</option><option value="daily">Daily</option><option value="weekly">Weekly</option></select></label></div><label>Dimensions (comma separated)<input value={dimensions} onChange={(event) => setDimensions(event.target.value)} /></label><footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="submit" className="primary-button"><Check size={17} />Create metric</button></footer></form></div>;
}

function PostHogConnectionForm({ sandboxMode, onClose, onSubmit }: { sandboxMode: boolean; onClose: () => void; onSubmit: (config: { host: string; projectId: string; personalApiKey: string }) => void }) {
  const [host, setHost] = useState("https://eu.posthog.com");
  const [projectId, setProjectId] = useState("");
  const [personalApiKey, setPersonalApiKey] = useState("");
  return <div className="modal-backdrop" role="presentation"><form className="goal-modal experiment-modal connection-modal" onSubmit={(event) => { event.preventDefault(); onSubmit({ host, projectId, personalApiKey }); }}><header><div><span className="eyebrow">PostHog connection</span><h2>Connect read-only aggregate analytics.</h2><p>The API key is encrypted in the Worker and never returned to this dashboard or sent to the model.</p></div><button className="icon-button" type="button" onClick={onClose} aria-label="Close"><X size={18} /></button></header>{sandboxMode ? <div className="form-hint"><FlaskConical size={15} /><span><strong>Sandbox locks live reads.</strong><br />Deploy with <code>SANDBOX_MODE=false</code> before connecting PostHog. Sandbox test experiments continue to work without a connection.</span></div> : <><label>PostHog host<select value={host} onChange={(event) => setHost(event.target.value)}><option value="https://eu.posthog.com">EU Cloud</option><option value="https://us.posthog.com">US Cloud</option></select></label><label>Project ID<input value={projectId} onChange={(event) => setProjectId(event.target.value)} inputMode="numeric" placeholder="e.g. 12345" required /></label><label>Personal API key<input type="password" value={personalApiKey} onChange={(event) => setPersonalApiKey(event.target.value)} autoComplete="off" placeholder="Read-only key with insight:read" required /></label><p className="connection-scope"><ShieldCheck size={15} />Verification lists saved insights only. The scheduled monitor reads aggregate insight results and stores dated snapshots.</p></>}<footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button>{!sandboxMode && <button type="submit" className="primary-button"><Activity size={17} />Verify read access</button>}</footer></form></div>;
}

function MetricCard({ icon, label, value, detail, tone }: { icon: React.ReactNode; label: string; value: string; detail: string; tone: string }) { return <article className={`metric-card metric-${tone}`}><div className="metric-icon">{icon}</div><span>{label}</span><strong>{value}</strong><small>{detail}</small></article>; }
function Detail({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) { return <div className="detail"><span>{icon}{label}</span><strong>{value}</strong></div>; }
function ChannelMark({ channel }: { channel: string }) { return <div className={`channel-mark channel-${channel}`} title={channel.replaceAll("_", " ")}>{channel === "sandbox" ? <FlaskConical size={16} /> : channel === "resend" ? <Send size={16} /> : channel === "posthog" ? <Activity size={16} /> : channel === "slack" ? <Slack size={16} /> : channel === "media" ? <ImagePlus size={16} /> : <Radio size={16} />}</div>; }
function Pipeline({ experiments }: { experiments: Experiment[] }) { return <div className="pipeline">{experiments.slice(0, 4).map((experiment) => <div className="pipeline-row" key={experiment.id}><ChannelMark channel={experiment.channel} /><div><strong>{experiment.title}</strong><span>{experiment.optimizationMetric}</span></div><span className={`status-badge status-${experiment.status}`}>{statusLabel[experiment.status]}</span></div>)}</div>; }
function NavButton({ icon, label, active, count, onClick }: { icon: React.ReactNode; label: string; active: boolean; count?: number; onClick: () => void }) { return <button className={`nav-row ${active ? "active" : ""}`} onClick={onClick}>{icon}<span>{label}</span>{count ? <b>{count}</b> : null}</button>; }
function BookIcon() { return <Eye size={18} />; }
function titleFor(view: View) { return view === "command" ? "Command" : view === "metrics" ? "Metrics" : view === "channels" ? "Channels" : view === "data" ? "Data" : view === "experiments" ? "Experiments" : view === "learning" ? "Learning cards" : "Connections"; }
