# Entrepreneurial Centre Roadmap

## Product outcome

Give a small growth team a trustworthy control plane for growth: connect its
data, define what success means, choose or create an experiment, approve any
external action, and see the evidence needed to scale, stop, or iterate.

The product must never present a simulated, inferred, or stale value as a
verified outcome. AI proposes and explains; users own metrics, budgets,
approval, and the final decision.

## Current State

The app has a usable sandbox, goals, experiment proposals, approval gates,
learning cards, a manual experiment creator, and early Metrics and Channels
views. It now exposes metric definitions, source health, snapshot history, and
a safe PostHog saved-insight ingestion path. It does not yet calculate
experiment lift or provide complete metric registry filtering and attribution.

**Production readiness: approximately 66%.** Phase 0 is complete. Phase 1 now
has the first read-only PostHog vertical slice: encrypted connection setup,
saved-insight mapping, idempotent aggregate snapshots, sync status, and an
inspectable metric detail view. Cohort discovery, retry/backoff, activity logs,
and broader registry controls remain in Phase 1 work.

## Phase 0 - Establish The Data Contract (50% -> 58%)

**Status: complete for the local product baseline.**

**Goal:** Make the meaning and trust level of every number unambiguous before
adding more automation.

- Define a metric registry model: owner, description, type, source, formula or
  PostHog definition, unit, dimensions, baseline, target, guardrails, cadence,
  and status.
- Define a source model: provider account, access scope, sync schedule, last
  successful sync, freshness SLA, failures, and whether data is observed,
  modeled, or simulated.
- Define a result model: exposure, control, variants, value, sample size,
  spend, attribution model/window, lift, uncertainty, and data-quality state.
- Record metric-definition versions so historical experiment results retain the
  definition used when they were decided.
- Make Sandbox data visually and structurally distinct from live data.

**Exit criteria:** Every UI value identifies its source, timestamp, and trust
level. A metric cannot be selected for a live goal until it has a definition and
an eligible data source.

## Phase 1 - Build The Measurement Foundation (58% -> 70%)

**Goal:** Let users manage actual business metrics instead of free-text metric
names.

- Build the Metric Registry with list, search, filters, ownership, definitions,
  used-by relationships, and an immutable activity log.
- Wire the existing `metric_snapshots` store into the API and dashboard.
- Implement read-only PostHog metric, insight, cohort, and aggregate query
  discovery. Do not send person-level data to the model.
- Add scheduled snapshot ingestion, idempotency, retry, watermarks, and
  connection-health reporting.
- Create a metric-detail screen with current value, trend, baseline, target,
  guardrail, source, freshness, dimensions, and linked goals/experiments.
- Let an admin map a goal to a registered metric and select primary, secondary,
  and guardrail metrics for an experiment.

**Exit criteria:** A connected PostHog workspace can populate a metric trend;
users can trace every displayed metric to a definition and successful source
sync; Sandbox results cannot appear in live totals.

## Phase 2 - Make Performance And Attribution Legible (70% -> 80%)

**Goal:** Make it obvious what is moving, why the team believes it, and which
channel is receiving credit.

- Replace the separate Metrics and Channels destinations with a Performance
  space: Overview, Metrics, Channels, and Data Health.
- Add a portfolio scorecard: active goals, current-versus-target movement,
  experiment contribution, guardrail alerts, budget used, and decisions due.
- Add channel reporting for spend, delivery, attributed conversion/revenue,
  efficiency metric, active experiments, freshness, and source coverage.
- Require an explicit attribution model, attribution window, and source of
  truth for each channel report. Show provider-reported and product-analytics
  values separately when they disagree.
- Add data-quality and insufficient-evidence states rather than implying a win
  or loss from sparse data.
- Provide drill-down by date range, audience, campaign, experiment, and metric
  dimension, with saved views for operators.

**Exit criteria:** A user can answer, from one screen: what is the goal, where
the number comes from, whether it is fresh, what changed, and which
experiments/channels plausibly contributed.

## Phase 3 - Complete The Experiment Operating System (80% -> 88%)

**Goal:** Turn experiment records into a scalable, steerable portfolio.

- Add portfolio search, status/channel/metric/owner/tag filters, sorting,
  archive behavior, saved views, and a concise table mode.
- Add experiment templates for product, lifecycle email, paid acquisition,
  organic social, and research-only tests.
- Add a structured lifecycle: idea, drafted, needs data, awaiting approval,
  scheduled, running, paused, completed, stopped, and archived.
- Add explicit controls to pause, stop, duplicate, reassign, comment, and
  record a decision. Surface the audit trail in the experiment detail.
- Add an experiment-results panel with control/variant comparison, metric
  trends, spend, exposure, sample thresholds, diagnostics, and a recommended
  next action.
- Add learning-card synthesis only after result data is available; preserve
  citations, metric-definition version, and approval snapshot.

**Exit criteria:** A growth operator can create, review, run, monitor, close,
and reuse a test without relying on a spreadsheet or hidden system state.

## Phase 4 - Turn On Controlled Live Execution (88% -> 94%)

**Goal:** Connect the first real channels while retaining approval and spend
control.

- Deploy Cloudflare Access, D1, R2, Queues, Cron Triggers, secrets, and
  workspace roles in a non-production environment first.
- Complete OAuth connection lifecycle, encrypted credential storage, revoked
  token handling, capability discovery, and a source-health screen.
- Launch PostHog as the first live read-only measurement adapter.
- Launch Resend as the first controlled write adapter: consent resolution on
  the server, UTM generation, preview, exact audience count, approval snapshot,
  idempotent send, and delivery metrics.
- Add Slack approval cards that show exact copy, audience, schedule, metric,
  spend caps, and replay-safe action handling.
- Add one paid channel only after its provider access, optimization event,
  audience constraints, budget guardrails, and reporting adapter pass contract
  tests. Do not parallelize all eight channel integrations.

**Exit criteria:** A live email experiment can be approved once, executed once,
measured from real sources, paused safely, and audited end to end.

## Phase 5 - Production Hardening And Expansion (94% -> 100%)

**Goal:** Make the product reliable enough for daily operating use and expand
channels deliberately.

- Add rate-limit handling, durable retries, dead-letter review, idempotency,
  webhook verification, incident alerts, backups, and retention policies.
- Add role/permission tests, audit export, access review, security logging, and
  secret rotation procedures.
- Add data reconciliation between PostHog, channel providers, and the selected
  business source of truth.
- Add AI evaluation controls: schema validation, citation requirements,
  prompt/version logging, proposal quality review, and human override.
- Add provider adapters in value order, only after each passes OAuth/app-review,
  publish, pause, reporting, and duplicate-delivery tests.
- Run browser E2E, Worker integration, Slack interaction, and provider contract
  suites in CI; define release and rollback runbooks.

**Exit criteria:** Daily operations, a provider outage, a duplicate approval,
and a revoked connection are all observable, recoverable, and safe.

## UX Principles For Every Phase

1. Start each session with the decision that needs attention, then show the
   evidence behind it.
2. Every metric and channel number carries source, timestamp, attribution
   method, and trust state.
3. Do not hide actions: users can create, edit, pause, stop, duplicate, and
   inspect from the portfolio and detail screens.
4. Use explicit empty states that instruct the next setup action.
5. Keep AI recommendations reversible, explainable, and approval-gated.

## Recommended Delivery Order

1. Phase 0 and Phase 1 before any new channel adapter.
2. Phase 2 and Phase 3 before broad AI autonomy.
3. Phase 4 with PostHog plus Resend as the first live vertical slice.
4. Phase 5 and then one paid/organic provider at a time, based on the team’s
   actual acquisition mix.
