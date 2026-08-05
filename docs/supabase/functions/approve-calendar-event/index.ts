import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const { draft_id, calendar_access_token } = await request.json();
  if (!draft_id || !calendar_access_token) {
    return json({ error: "draft_id and calendar_access_token are required" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data: draft, error: draftError } = await supabase
    .from("inbox_drafts")
    .select("*, households(shared_calendar_id)")
    .eq("id", draft_id)
    .single();

  if (draftError || !draft) {
    return json({ error: "Draft not found", detail: draftError?.message }, 404);
  }

  if (!draft.due_at) {
    await markRetry(supabase, draft_id, "A due date is required before creating a Google Calendar event.");
    return json({ error: "Missing due date" }, 422);
  }

  const calendarId = draft.households?.shared_calendar_id;
  if (!calendarId) {
    await markRetry(supabase, draft_id, "Google Calendar is not connected for this household.");
    return json({ error: "Missing shared calendar" }, 422);
  }

  const eventResponse = await fetch(
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${calendar_access_token}`,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        summary: draft.title,
        description: [
          `Source: ${draft.source_subject}`,
          `From: ${draft.source_from}`,
          `Gmail message: ${draft.gmail_message_id}`
        ].join("\n"),
        start: { dateTime: draft.due_at },
        end: { dateTime: draft.due_at },
        reminders: {
          useDefault: false,
          overrides: [
            { method: "popup", minutes: 1440 },
            { method: "popup", minutes: 60 }
          ]
        }
      })
    }
  );

  if (!eventResponse.ok) {
    const detail = await eventResponse.text();
    await markRetry(supabase, draft_id, detail);
    return json({ error: "Calendar creation failed", detail }, 502);
  }

  const event = await eventResponse.json();
  await supabase.from("inbox_drafts").update({
    status: "approved",
    google_event_id: event.id,
    google_event_url: event.htmlLink,
    last_error: null,
    updated_at: new Date().toISOString()
  }).eq("id", draft_id);

  await supabase.from("google_object_mappings").insert({
    household_id: draft.household_id,
    draft_id,
    object_type: "calendar_event",
    google_id: event.id,
    google_url: event.htmlLink,
    last_seen_at: new Date().toISOString()
  });

  await supabase.from("approval_events").insert({
    household_id: draft.household_id,
    draft_id,
    action: "approved_to_calendar",
    metadata: { google_event_id: event.id }
  });

  return json({ google_event_id: event.id, google_event_url: event.htmlLink });
});

async function markRetry(supabase: ReturnType<typeof createClient>, draftId: string, message: string) {
  await supabase.from("inbox_drafts").update({
    status: "calendar_retry_required",
    last_error: message,
    updated_at: new Date().toISOString()
  }).eq("id", draftId);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });
}
