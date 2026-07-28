import type { DashboardPayload, Experiment, Goal, LearningCard, MetricDefinition, MetricSnapshot, ProviderConnection } from "../shared/types";

const now = "2026-07-28T08:00:00.000Z";

export const demoGoal: Goal = {
  id: "goal_activation",
  title: "Increase activated workspaces",
  metricDefinitionId: "metric_activation_funnel",
  metricKind: "funnel",
  metricName: "Signup to first shared project",
  baseline: 31,
  target: 45,
  unit: "%",
  deadline: "2026-09-30",
  guardrail: "Trial-to-paid conversion must not fall below 8%.",
  monthlyBudgetCents: 350000,
  status: "active"
};

export const demoExperiments: Experiment[] = [
  {
    id: "exp_activation_email",
    goalId: demoGoal.id,
    title: "Bring high-intent trials back to their first project",
    surface: "email",
    channel: "resend",
    status: "awaiting_approval",
    hypothesis: "A concise setup email sent to trials that started but did not create a shared project will improve activation.",
    channelRationale: "PostHog identifies a large, consented high-intent cohort and lifecycle email is the lowest-cost channel.",
    expectedImpact: "high",
    confidence: 0.78,
    audienceId: "audience_high_intent",
    optimizationMetric: "Created first shared project",
    successRule: "Lift activation from 31% to at least 36% within 14 days, without reducing trial-to-paid conversion.",
    decisionWindowDays: 14,
    variants: [
      {
        id: "variant_control",
        name: "Direct setup prompt",
        headline: "Your first shared project takes two minutes",
        body: "Invite one teammate, pick a template, and see the first project come to life.",
        assetIds: [],
        trackingUrl: "https://product.example.com/onboarding"
      },
      {
        id: "variant_social_proof",
        name: "Team proof",
        headline: "The fastest teams make their first project together",
        body: "A short guided start helps the whole team see value in the first session.",
        assetIds: [],
        trackingUrl: "https://product.example.com/onboarding"
      }
    ],
    spend: {},
    createdAt: now,
    updatedAt: now
  },
  {
    id: "exp_linkedin_story",
    goalId: demoGoal.id,
    title: "Test a founder story against activation friction",
    surface: "paid",
    channel: "linkedin",
    status: "blocked",
    hypothesis: "A founder-led LinkedIn story about reducing setup friction will attract higher-intent B2B trials.",
    channelRationale: "The target audience has strong LinkedIn concentration, but the advertising connection is still awaiting access.",
    expectedImpact: "medium",
    confidence: 0.64,
    optimizationMetric: "Activated workspace",
    successRule: "Acquire activated workspaces below €75 each over a 21-day decision window.",
    decisionWindowDays: 21,
    variants: [
      {
        id: "variant_founder_story",
        name: "Founder story",
        headline: "The setup step teams keep skipping",
        body: "A founder note on the small behavior that predicts successful teams.",
        assetIds: [],
        trackingUrl: "https://product.example.com/activation"
      }
    ],
    spend: {
      dailyCents: 5000,
      totalCents: 60000,
      startAt: "2026-08-03T09:00:00.000Z",
      stopAt: "2026-08-24T18:00:00.000Z"
    },
    createdAt: now,
    updatedAt: now
  },
  {
    id: "exp_first_project_flag",
    goalId: demoGoal.id,
    title: "Test a guided first-project checklist",
    surface: "product",
    channel: "posthog",
    status: "awaiting_engineering",
    hypothesis: "A lightweight checklist will reduce the gap between sign-up and first shared project creation.",
    channelRationale: "The funnel drop-off is product-led and should be tested alongside channel work.",
    expectedImpact: "high",
    confidence: 0.71,
    optimizationMetric: "Created first shared project",
    successRule: "Increase the activation funnel by 10% with no increase in onboarding abandonment.",
    decisionWindowDays: 21,
    variants: [
      {
        id: "variant_checklist",
        name: "Checklist",
        headline: "Get to value faster",
        body: "Show progress through the first shared project setup.",
        assetIds: [],
        trackingUrl: "https://product.example.com"
      }
    ],
    spend: {},
    engineeringFlagKey: "guided_first_project_checklist",
    engineeringBrief: "Implement the registered PostHog flag with control and checklist variants, capture checklist_viewed and shared_project_created.",
    createdAt: now,
    updatedAt: now
  }
];

export const demoConnections: ProviderConnection[] = [
  {
    id: "connection_sandbox",
    provider: "sandbox",
    label: "Built-in Sandbox",
    status: "connected",
    capabilities: ["read_channel_metrics"],
    detail: "Runs a complete simulated experiment and learning card locally. It never contacts a provider or audience."
  },
  {
    id: "connection_posthog",
    provider: "posthog",
    label: "PostHog product analytics",
    status: "pending_access",
    capabilities: [],
    detail: "Not connected. Sandbox includes only a simulated measurement so the workflow can be tested without product data."
  },
  {
    id: "connection_resend",
    provider: "resend",
    label: "Lifecycle email",
    status: "connected",
    capabilities: ["send_email", "read_channel_metrics"],
    detail: "Consent-gated delivery only. The model never receives recipient identities."
  },
  {
    id: "connection_slack",
    provider: "slack",
    label: "#growth-approvals",
    status: "connected",
    capabilities: [],
    detail: "Slack is the primary approval surface for publish, reject, and pause actions."
  },
  ...["linkedin", "meta", "tiktok", "snapchat", "google_ads", "x", "reddit", "pinterest"].map((provider) => ({
    id: `connection_${provider}`,
    provider: provider as ProviderConnection["provider"],
    label: provider.replace("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase()),
    status: "pending_access" as const,
    capabilities: [],
    detail: "Connect a business account and complete the provider’s access review before AI can recommend a live action here."
  }))
];

export const demoLearningCards: LearningCard[] = [
  {
    id: "card_activation_email",
    experimentId: "exp_activation_email",
    evidence: [
      {
        id: "evidence_funnel",
        source: "posthog",
        label: "Activation funnel",
        detail: "31% of trials create a shared project; the largest drop-off occurs after initial workspace creation.",
        capturedAt: "2026-07-28T07:00:00.000Z"
      },
      {
        id: "evidence_cohort",
        source: "posthog",
        label: "Eligible audience",
        detail: "842 consented trials completed initial setup but have not created a shared project.",
        capturedAt: "2026-07-28T07:00:00.000Z"
      }
    ],
    expectedImpact: "high",
    confidence: 0.78,
    outcome: "pending",
    outcomeSummary: "Awaiting approval and launch.",
    nextAction: "Approve the consented lifecycle email in Slack."
  }
];

export const demoMetricDefinitions: MetricDefinition[] = [
  {
    id: "metric_activation_funnel",
    name: "Signup to first shared project",
    description: "Percentage of newly signed-up workspaces that create their first shared project within the activation window.",
    kind: "funnel",
    sourceProvider: "posthog",
    calculation: "Created first shared project / completed signup",
    unit: "%",
    dimensions: ["plan", "acquisition_channel", "workspace_size"],
    cadence: "daily",
    trustLevel: "unavailable",
    status: "needs_connection",
    ownerMemberId: "member_admin",
    version: 1,
    createdAt: now,
    updatedAt: now
  }
];

export const demoMetricSnapshots: MetricSnapshot[] = [
  {
    id: "snapshot_activation_sandbox",
    metricDefinitionId: "metric_activation_funnel",
    sourceProvider: "sandbox",
    value: 31,
    dimensions: { environment: "sandbox" },
    trustLevel: "simulated",
    quality: "verified",
    capturedAt: now
  }
];

export const demoDashboard: DashboardPayload = {
  workspace: { id: "workspace_demo", name: "Northstar growth", productName: "Northstar", timezone: "Europe/Amsterdam" },
  me: { id: "member_admin", name: "Taylor Morgan", email: "taylor@example.com", role: "admin", slackUserId: "U_DEMO_ADMIN" },
  goals: [demoGoal],
  experiments: demoExperiments,
  learningCards: demoLearningCards,
  connections: demoConnections,
  dataSources: [
    {
      id: "source_sandbox",
      provider: "sandbox",
      label: "Built-in Sandbox",
      status: "connected",
      trustLevel: "simulated",
      freshness: "fresh",
      lastSyncedAt: now,
      cadence: "daily",
      scope: "Local workflow samples only",
      detail: "Simulated results exercise the workflow but never change production totals."
    },
    {
      id: "source_posthog",
      provider: "posthog",
      label: "PostHog product analytics",
      status: "pending_access",
      trustLevel: "unavailable",
      freshness: "not_synced",
      cadence: "daily",
      scope: "Aggregate events, funnels, and cohorts",
      detail: "Connect PostHog and validate the activation funnel before using it for live decisions."
    },
    {
      id: "source_resend",
      provider: "resend",
      label: "Lifecycle email reporting",
      status: "connected",
      trustLevel: "unavailable",
      freshness: "not_synced",
      cadence: "daily",
      scope: "Aggregate delivery and engagement reporting",
      detail: "A delivery connection is configured, but no channel metric snapshot has been ingested."
    }
  ],
  metricDefinitions: demoMetricDefinitions,
  metricSnapshots: demoMetricSnapshots,
  audiences: [
    {
      id: "audience_high_intent",
      name: "High-intent trials with marketing consent",
      posthogCohortId: "cohort_328",
      estimatedPeople: 842,
      consentProperty: "marketing_consent",
      emailProperty: "email",
      eligible: true
    }
  ],
  engineeringBriefs: [
    {
      id: "brief_first_project",
      experimentId: "exp_first_project_flag",
      flagKey: "guided_first_project_checklist",
      variants: ["control", "checklist"],
      trackingRequirements: ["checklist_viewed", "shared_project_created"],
      status: "waiting_for_engineering"
    }
  ],
  sandboxMode: true,
  lastDailyMonitorAt: "2026-07-28T07:00:00.000Z",
  lastWeeklyPlanAt: "2026-07-28T08:00:00.000Z"
};
