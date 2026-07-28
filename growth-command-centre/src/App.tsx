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
import type { DashboardPayload, Experiment, Goal, ProviderConnection } from "../shared/types";

type View = "command" | "experiments" | "learning" | "connections";
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

export function App() {
  const [dashboard, setDashboard] = useState<DashboardPayload>(demoDashboard);
  const [view, setView] = useState<View>("command");
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string>();
  const [toast, setToast] = useState<Toast>();
  const [showGoalForm, setShowGoalForm] = useState(false);
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

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
    } catch (error) {
      setToast({ tone: "error", message: error instanceof Error ? error.message : "That action could not be completed." });
    } finally {
      setBusy(undefined);
    }
  };

  const activeGoal = dashboard.goals.find((goal) => goal.status === "active") ?? dashboard.goals[0];
  const selectedExperiment = useMemo(
    () => dashboard.experiments.find((experiment) => experiment.status === "awaiting_approval") ?? dashboard.experiments[0],
    [dashboard.experiments]
  );

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
          <NavButton icon={<FlaskConical size={18} />} label="Experiments" count={dashboard.experiments.filter((item) => item.status === "awaiting_approval").length} active={view === "experiments"} onClick={() => setView("experiments")} />
          <NavButton icon={<BookIcon />} label="Learning" active={view === "learning"} onClick={() => setView("learning")} />
          <NavButton icon={<Link2 size={18} />} label="Connections" active={view === "connections"} onClick={() => setView("connections")} />
        </nav>
        <div className="sidebar-bottom">
          <div className="member-chip"><div className="member-avatar">{dashboard.me.name.slice(0, 1)}</div><div><strong>{dashboard.me.name}</strong><span>{dashboard.me.role}</span></div></div>
          <button className="nav-row muted"><Settings2 size={18} /> Settings</button>
        </div>
      </aside>

      <main className="main-content">
        <header className="topbar">
          <button className="icon-button mobile-only" onClick={() => setMobileNavOpen(true)} aria-label="Open navigation"><Menu size={20} /></button>
          <div className="topbar-title"><span className="eyebrow">{view === "command" ? "Growth operating system" : view}</span><h1>{titleFor(view)}</h1></div>
          <div className="topbar-actions">
            <div className="status-note"><span className="status-dot" />Data refreshed {dateLabel(dashboard.lastDailyMonitorAt)}</div>
            <button className="icon-button" title="Refresh workspace" onClick={() => void refresh()} disabled={loading}><RefreshCw size={18} className={loading ? "spin" : ""} /></button>
            <button className="primary-button" onClick={() => setShowGoalForm(true)}><Plus size={18} /> New goal</button>
          </div>
        </header>

        {toast && <div className={`toast toast-${toast.tone}`} role="status">{toast.tone === "success" ? <Check size={16} /> : toast.tone === "error" ? <CircleAlert size={16} /> : <BellRing size={16} />}{toast.message}<button onClick={() => setToast(undefined)} aria-label="Dismiss"><X size={15} /></button></div>}

        {view === "command" && activeGoal && <CommandView
          goal={activeGoal}
          experiment={selectedExperiment}
          dashboard={dashboard}
          busy={busy}
          onMonitor={() => void run("monitor", api.monitor, "Daily monitor completed. Slack will receive any urgent attention items.")}
          onPlan={() => void run("plan", api.weeklyPlan, "A new weekly experiment proposal was generated.")}
          onApprove={(experiment) => void run(`approve-${experiment.id}`, () => api.approve(experiment.id), "Approved and queued. The provider will not receive a duplicate launch request.")}
          onReject={(experiment) => void run(`reject-${experiment.id}`, () => api.reject(experiment.id), "Experiment rejected and removed from the approval queue.")}
        />}
        {view === "experiments" && <ExperimentsView dashboard={dashboard} busy={busy} onApprove={(experiment) => void run(`approve-${experiment.id}`, () => api.approve(experiment.id), "Approved and queued for execution.")} onReject={(experiment) => void run(`reject-${experiment.id}`, () => api.reject(experiment.id), "Experiment rejected.")} />}
        {view === "learning" && <LearningView dashboard={dashboard} />}
        {view === "connections" && <ConnectionsView connections={dashboard.connections} />}
      </main>

      {showGoalForm && <GoalForm onClose={() => setShowGoalForm(false)} onSubmit={(goal) => void run("goal", () => api.createGoal(goal), "Goal created. It will be included in the next weekly plan.").then(() => setShowGoalForm(false))} />}
    </div>
  );
}

function CommandView({ goal, experiment, dashboard, busy, onMonitor, onPlan, onApprove, onReject }: {
  goal: Goal; experiment?: Experiment; dashboard: DashboardPayload; busy?: string; onMonitor: () => void; onPlan: () => void; onApprove: (experiment: Experiment) => void; onReject: (experiment: Experiment) => void;
}) {
  // The baseline is the first recorded value, so the current dashboard cannot
  // infer progress until the monitor has collected a newer metric snapshot.
  const progress = 0;
  const ready = dashboard.experiments.filter((item) => item.status === "awaiting_approval").length;
  const live = dashboard.experiments.filter((item) => item.status === "live").length;
  return <div className="view-stack">
    <section className="goal-band">
      <div className="goal-copy"><span className="eyebrow"><Target size={14} /> Active outcome</span><h2>{goal.title}</h2><p>Move <strong>{goal.metricName}</strong> from {goal.baseline}{goal.unit} to {goal.target}{goal.unit} by {new Intl.DateTimeFormat("en", { month: "long", day: "numeric" }).format(new Date(goal.deadline))}.</p></div>
      <div className="goal-measure"><div className="goal-numbers"><strong>{goal.baseline}{goal.unit}</strong><span>now</span><ArrowUpRight size={18} /><strong>{goal.target}{goal.unit}</strong><span>target</span></div><div className="progress-track"><div style={{ width: `${Math.max(8, progress)}%` }} /></div><small>{goal.guardrail}</small></div>
    </section>
    <section className="action-row" aria-label="Automation controls">
      <div><span className="eyebrow">Autopilot cadence</span><strong>Daily monitor. Weekly plan.</strong><span>AI works in the background; only external actions wait for an admin.</span></div>
      <div className="action-buttons"><button className="secondary-button" disabled={busy === "monitor"} onClick={onMonitor}>{busy === "monitor" ? <LoaderCircle className="spin" size={17} /> : <Activity size={17} />} Run monitor</button><button className="dark-button" disabled={busy === "plan"} onClick={onPlan}>{busy === "plan" ? <LoaderCircle className="spin" size={17} /> : <Bot size={17} />} Generate plan</button></div>
    </section>
    <section className="metric-grid" aria-label="Growth summary">
      <MetricCard icon={<FlaskConical size={19} />} label="Awaiting approval" value={String(ready)} detail="Slack is the decision surface" tone="amber" />
      <MetricCard icon={<Radio size={19} />} label="Live experiments" value={String(live)} detail="Guardrails monitored daily" tone="teal" />
      <MetricCard icon={<UsersRound size={19} />} label="Consented audience" value={dashboard.audiences.reduce((total, item) => total + item.estimatedPeople, 0).toLocaleString()} detail="AI sees aggregate eligibility only" tone="blue" />
      <MetricCard icon={<BarChart3 size={19} />} label="Paid budget" value={formatCents(goal.monthlyBudgetCents)} detail="Campaign caps required per approval" tone="purple" />
    </section>
    {experiment && <ApprovalPanel experiment={experiment} audienceName={dashboard.audiences.find((item) => item.id === experiment.audienceId)?.name} busy={busy} onApprove={onApprove} onReject={onReject} />}
    <section className="section-grid">
      <div className="section-panel"><div className="section-heading"><div><span className="eyebrow">Active work</span><h3>Experiment pipeline</h3></div><button className="text-button">View all <ChevronRight size={15} /></button></div><Pipeline experiments={dashboard.experiments} /></div>
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

function ExperimentsView({ dashboard, busy, onApprove, onReject }: { dashboard: DashboardPayload; busy?: string; onApprove: (experiment: Experiment) => void; onReject: (experiment: Experiment) => void }) {
  return <div className="view-stack"><section className="page-intro"><div><span className="eyebrow">Experiment system</span><h2>Every action earns a learning card.</h2><p>AI proposes. Your team reviews the bounded decision package. Measurement decides what happens next.</p></div><div className="legend"><span><i className="legend-dot awaiting" />Needs approval</span><span><i className="legend-dot live" />Live</span><span><i className="legend-dot blocked" />Blocked</span></div></section><section className="experiment-list">{dashboard.experiments.map((experiment) => <article className="experiment-row" key={experiment.id}><div className="experiment-channel"><ChannelMark channel={experiment.channel} /></div><div className="experiment-main"><div className="row-title"><h3>{experiment.title}</h3><span className={`status-badge status-${experiment.status}`}>{statusLabel[experiment.status]}</span></div><p>{experiment.hypothesis}</p><div className="row-meta"><span><Target size={14} />{experiment.optimizationMetric}</span><span><Clock3 size={14} />{experiment.decisionWindowDays} days</span><span><BarChart3 size={14} />{experiment.expectedImpact} impact</span></div></div><div className="experiment-actions">{experiment.status === "awaiting_approval" ? <><button className="icon-button" title="Reject experiment" onClick={() => onReject(experiment)} disabled={Boolean(busy)}><X size={17} /></button><button className="primary-button compact" onClick={() => onApprove(experiment)} disabled={Boolean(busy)}><Send size={16} />Approve</button></> : <button className="icon-button" title="View experiment"><MoreHorizontal size={19} /></button>}</div></article>)}</section></div>;
}

function LearningView({ dashboard }: { dashboard: DashboardPayload }) {
  return <div className="view-stack"><section className="page-intro"><div><span className="eyebrow">Institutional memory</span><h2>Learn once. Compound the result.</h2><p>Every experiment retains the evidence, outcome, and recommendation that led to the next decision.</p></div></section><section className="learning-grid">{dashboard.learningCards.map((card) => { const experiment = dashboard.experiments.find((item) => item.id === card.experimentId); return <article className="learning-card" key={card.id}><div className="card-top"><span className="eyebrow">{card.outcome === "pending" ? "In progress" : card.outcome}</span><span>{Math.round(card.confidence * 100)}% confidence</span></div><h3>{experiment?.title ?? "Experiment"}</h3><p>{card.outcomeSummary}</p><div className="evidence-list">{card.evidence.map((evidence) => <div key={evidence.id}><span className="evidence-source">{evidence.source.replace("_", " ")}</span><strong>{evidence.label}</strong><p>{evidence.detail}</p></div>)}</div><footer><Sparkles size={16} />{card.nextAction}</footer></article>; })}</section></div>;
}

function ConnectionsView({ connections }: { connections: ProviderConnection[] }) {
  const connected = connections.filter((connection) => connection.status === "connected");
  const awaiting = connections.filter((connection) => connection.status !== "connected");
  return <div className="view-stack"><section className="page-intro"><div><span className="eyebrow">Integration control plane</span><h2>AI chooses only from authorized capabilities.</h2><p>A platform never receives an external write until its account, scopes, and app review are fully connected.</p></div><div className="connection-summary"><strong>{connected.length}</strong><span>connected</span></div></section><section className="connection-section"><div className="section-heading"><div><span className="eyebrow">Ready now</span><h3>Authorized connections</h3></div></div><ConnectionGrid connections={connected} /></section><section className="connection-section"><div className="section-heading"><div><span className="eyebrow">Access required</span><h3>Channel registry</h3></div></div><ConnectionGrid connections={awaiting} /></section></div>;
}

function ConnectionGrid({ connections }: { connections: ProviderConnection[] }) { return <div className="connection-grid">{connections.map((connection) => <article className="connection-card" key={connection.id}><div className="connection-card-top"><ChannelMark channel={connection.provider} /><span className={`connection-state ${connection.status}`}>{connection.status === "connected" ? "Connected" : "Access required"}</span></div><h3>{connection.label}</h3><p>{connection.detail}</p><div className="capability-list">{connection.capabilities.length ? connection.capabilities.map((capability) => <span key={capability}>{capability.replaceAll("_", " ")}</span>) : <span>Configure connection</span>}</div><button className="text-button">{connection.status === "connected" ? "Manage" : "Connect"} <ArrowUpRight size={15} /></button></article>)}</div>; }

function GoalForm({ onClose, onSubmit }: { onClose: () => void; onSubmit: (goal: Omit<Goal, "id" | "status">) => void }) {
  const [title, setTitle] = useState("Increase activated workspaces"); const [metricName, setMetricName] = useState("Signup to first shared project"); const [baseline, setBaseline] = useState("31"); const [target, setTarget] = useState("45"); const [deadline, setDeadline] = useState("2026-09-30"); const [budget, setBudget] = useState("3500");
  return <div className="modal-backdrop" role="presentation"><form className="goal-modal" onSubmit={(event) => { event.preventDefault(); onSubmit({ title, metricKind: "funnel", metricName, baseline: Number(baseline), target: Number(target), unit: "%", deadline, guardrail: "Trial-to-paid conversion must remain stable.", monthlyBudgetCents: Number(budget) * 100 }); }}><header><div><span className="eyebrow">New growth outcome</span><h2>Set the result. AI will find the work.</h2></div><button className="icon-button" type="button" onClick={onClose} aria-label="Close"><X size={18} /></button></header><label>Outcome<input value={title} onChange={(event) => setTitle(event.target.value)} required /></label><label>PostHog metric<input value={metricName} onChange={(event) => setMetricName(event.target.value)} required /></label><div className="form-grid"><label>Baseline<input type="number" value={baseline} onChange={(event) => setBaseline(event.target.value)} required /></label><label>Target<input type="number" value={target} onChange={(event) => setTarget(event.target.value)} required /></label></div><div className="form-grid"><label>Deadline<input type="date" value={deadline} onChange={(event) => setDeadline(event.target.value)} required /></label><label>Monthly paid budget (EUR)<input type="number" min="0" value={budget} onChange={(event) => setBudget(event.target.value)} required /></label></div><footer><button type="button" className="secondary-button" onClick={onClose}>Cancel</button><button type="submit" className="primary-button"><Target size={17} />Create goal</button></footer></form></div>;
}

function MetricCard({ icon, label, value, detail, tone }: { icon: React.ReactNode; label: string; value: string; detail: string; tone: string }) { return <article className={`metric-card metric-${tone}`}><div className="metric-icon">{icon}</div><span>{label}</span><strong>{value}</strong><small>{detail}</small></article>; }
function Detail({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) { return <div className="detail"><span>{icon}{label}</span><strong>{value}</strong></div>; }
function ChannelMark({ channel }: { channel: string }) { return <div className={`channel-mark channel-${channel}`} title={channel.replaceAll("_", " ")}>{channel === "resend" ? <Send size={16} /> : channel === "posthog" ? <Activity size={16} /> : channel === "slack" ? <Slack size={16} /> : channel === "media" ? <ImagePlus size={16} /> : <Radio size={16} />}</div>; }
function Pipeline({ experiments }: { experiments: Experiment[] }) { return <div className="pipeline">{experiments.slice(0, 4).map((experiment) => <div className="pipeline-row" key={experiment.id}><ChannelMark channel={experiment.channel} /><div><strong>{experiment.title}</strong><span>{experiment.optimizationMetric}</span></div><span className={`status-badge status-${experiment.status}`}>{statusLabel[experiment.status]}</span></div>)}</div>; }
function NavButton({ icon, label, active, count, onClick }: { icon: React.ReactNode; label: string; active: boolean; count?: number; onClick: () => void }) { return <button className={`nav-row ${active ? "active" : ""}`} onClick={onClick}>{icon}<span>{label}</span>{count ? <b>{count}</b> : null}</button>; }
function BookIcon() { return <Eye size={18} />; }
function titleFor(view: View) { return view === "command" ? "Command" : view === "experiments" ? "Experiments" : view === "learning" ? "Learning cards" : "Connections"; }
