# Entrepreneurial Centre

Private growth command centre for one product team. It turns a measurable goal
into approved, tracked experiments across product, lifecycle, paid, and social
channels.

## Local development

```bash
cd growth-command-centre
npm install
npx wrangler d1 migrations apply entrepreneurial-centre --local
npm run worker:dev -- --local --port 8787
# In a second terminal:
npm run dev
```

Copy `.dev.vars.example` to `.dev.vars` before adding local secrets. The Worker
uses local D1, R2, and Queue emulation, so this workflow needs no Docker. The
dashboard has a visual demo fallback only when the Worker is not running.

## Run a connection-free test

With the local Worker running, open the dashboard and click **Run test
experiment** on Command. This uses the built-in Sandbox channel: it records an
admin approval snapshot, simulated publication, metric evidence, completed
outcome, learning card, and audit event. It does not resolve an audience, spend
money, call a marketing API, or require any credential.

`SANDBOX_MODE=true` is the local default. It blocks every non-sandbox execution
job before a provider can be called. Set `SANDBOX_MODE=false` only in a deployed
workspace after Cloudflare Access, encrypted credentials, and the relevant
provider adapter have been configured.

## Connect PostHog measurement

PostHog is the first live, read-only measurement path. It is deliberately
unavailable while `SANDBOX_MODE=true`.

1. Deploy a non-sandbox environment with `CREDENTIAL_ENCRYPTION_KEY` set as a
   Worker secret.
2. In **Connections**, choose **Connect PostHog** and provide the EU or US host,
   project id, and a personal API key limited to `insight:read`.
3. The Worker verifies the key by listing saved insights, encrypts the connection
   configuration before D1 storage, and never returns the key to the browser.
4. Create a metric definition and map it to one saved insight. The daily monitor
   reads only that insight's aggregate output and retains dated metric snapshots.

The model receives aggregate values, labels, and cohort names/counts only. It
does not receive people, raw events, or personal properties. A failed sync is
shown alongside the last successful source timestamp so operators can distinguish
stale data from unavailable data.

## Deploy prerequisites

1. Create the D1 database, R2 bucket, and Queue named in `wrangler.jsonc`, then
   replace the D1 database id.
2. Configure Cloudflare Access for the custom domain and set `APP_BASE_URL`.
3. Add Worker secrets: `CREDENTIAL_ENCRYPTION_KEY`, `SLACK_SIGNING_SECRET`,
   `SLACK_BOT_TOKEN`, `ANTHROPIC_API_KEY`, and provider-specific OAuth/client
   credentials as each integration is approved. Admins send provider settings
   only to `PUT /api/connections/:provider/config`; the Worker encrypts them
   before D1 storage and never returns them to the dashboard or model.
4. Apply migrations with `wrangler d1 migrations apply entrepreneurial-centre`.

Providers are intentionally unavailable until their connection is authenticated
and its platform capability has been approved. No provider write happens before
an admin approval, whether it is made in Slack or the dashboard.

`SEARCH_API_ENDPOINT` is optional. When configured, it must accept a `q` query
parameter and return `{ "results": [{ "title", "url", "snippet" }] }`. Weekly
planning records those sources on the learning card; without it, planning uses
workspace evidence only.
