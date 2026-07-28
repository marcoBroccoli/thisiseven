import type { ExecutionJob } from "../shared/types";

export interface Env {
  DB: D1Database;
  ASSETS: R2Bucket;
  EXECUTION_QUEUE: Queue<ExecutionJob>;
  APP_BASE_URL: string;
  DEMO_MODE: string;
  CREDENTIAL_ENCRYPTION_KEY?: string;
  SLACK_SIGNING_SECRET?: string;
  SLACK_BOT_TOKEN?: string;
  SLACK_APPROVAL_CHANNEL?: string;
  ANTHROPIC_API_KEY?: string;
  ANTHROPIC_MODEL?: string;
  SEARCH_API_ENDPOINT?: string;
  SEARCH_API_TOKEN?: string;
}
