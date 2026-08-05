import type { Experiment } from "../shared/types";
import type { Env } from "./env";

function hex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index += 1) difference |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return difference === 0;
}

export async function verifySlackRequest(request: Request, body: string, secret: string | undefined): Promise<boolean> {
  if (!secret) return false;
  const timestamp = request.headers.get("x-slack-request-timestamp");
  const signature = request.headers.get("x-slack-signature");
  if (!timestamp || !signature || Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`v0:${timestamp}:${body}`));
  return safeEqual(signature, `v0=${hex(signed)}`);
}

export async function notifySlackApproval(env: Env, experiment: Experiment): Promise<boolean> {
  if (!env.SLACK_BOT_TOKEN || !env.SLACK_APPROVAL_CHANNEL) return false;
  const value = JSON.stringify({ experimentId: experiment.id });
  const response = await fetch("https://slack.com/api/chat.postMessage", {
    method: "POST",
    headers: { authorization: `Bearer ${env.SLACK_BOT_TOKEN}`, "content-type": "application/json; charset=utf-8" },
    body: JSON.stringify({
      channel: env.SLACK_APPROVAL_CHANNEL,
      text: `Approval required: ${experiment.title}`,
      blocks: [
        { type: "header", text: { type: "plain_text", text: "Growth approval required" } },
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: `*${experiment.title}*\n${experiment.hypothesis}\n\n*Channel:* ${experiment.channel}\n*Metric:* ${experiment.optimizationMetric}\n*Decision window:* ${experiment.decisionWindowDays} days`
          }
        },
        {
          type: "actions",
          elements: [
            { type: "button", text: { type: "plain_text", text: "Approve" }, style: "primary", action_id: "growth.approve", value },
            { type: "button", text: { type: "plain_text", text: "Reject" }, style: "danger", action_id: "growth.reject", value },
            { type: "button", text: { type: "plain_text", text: "Open dashboard" }, url: `${env.APP_BASE_URL}/?experiment=${experiment.id}`, action_id: "growth.open" }
          ]
        }
      ]
    })
  });
  return response.ok && (await response.json<{ ok?: boolean }>()).ok === true;
}
