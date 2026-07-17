import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type GmailMessageList = {
  messages?: Array<{ id: string }>;
};

type GmailMessage = {
  id: string;
  snippet?: string;
  payload?: {
    headers?: Array<{ name: string; value: string }>;
  };
  internalDate?: string;
};

const labelName = "HouseholdTodo";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const { household_id, gmail_access_token } = await request.json();
  if (!household_id || !gmail_access_token) {
    return json({ error: "household_id and gmail_access_token are required" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const listResponse = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?q=label:${encodeURIComponent(labelName)}`,
    { headers: { Authorization: `Bearer ${gmail_access_token}` } }
  );

  if (!listResponse.ok) {
    return json({ error: "Failed to list Gmail messages", detail: await listResponse.text() }, 502);
  }

  const list = await listResponse.json() as GmailMessageList;
  const messages = list.messages ?? [];
  const imported: string[] = [];

  for (const message of messages) {
    const detailResponse = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`,
      { headers: { Authorization: `Bearer ${gmail_access_token}` } }
    );

    if (!detailResponse.ok) {
      continue;
    }

    const detail = await detailResponse.json() as GmailMessage;
    const headers = new Map((detail.payload?.headers ?? []).map((header) => [header.name.toLowerCase(), header.value]));
    const subject = headers.get("subject") ?? "(No subject)";
    const from = headers.get("from") ?? "unknown";
    const receivedAt = detail.internalDate ? new Date(Number(detail.internalDate)).toISOString() : null;

    const { error } = await supabase.from("inbox_drafts").upsert({
      household_id,
      gmail_message_id: detail.id,
      gmail_label: labelName,
      source_subject: subject,
      source_from: from,
      source_received_at: receivedAt,
      source_preview: detail.snippet ?? "",
      title: subject,
      extraction_confidence: 0,
      extraction_evidence: detail.snippet ? [detail.snippet] : [],
      status: "pending_approval"
    }, {
      onConflict: "household_id,gmail_message_id"
    });

    if (!error) {
      imported.push(detail.id);
    }
  }

  return json({ imported });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}
