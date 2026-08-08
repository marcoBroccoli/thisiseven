package api

import (
	"net/http"
	"time"
)

// The ops page answers the two questions support actually gets asked: "why has
// my mail stopped turning into todos?" and "why did this not show up in my
// calendar?". Both are answered from evend's own bookkeeping columns.

type mailboxRow struct {
	MemberID      string  `json:"member_id"`
	MemberName    string  `json:"member_name"`
	HouseholdID   string  `json:"household_id"`
	HouseholdName string  `json:"household_name"`
	Email         string  `json:"email"`
	ClientKind    string  `json:"client_kind"`
	ConnectedAt   string  `json:"connected_at"`
	LastSyncAt    *string `json:"last_sync_at"`
	LastSyncCount int     `json:"last_sync_count"`
	StaleHours    *int    `json:"stale_hours"`
	Scanned       int     `json:"scanned_messages"`
	Actionable    int     `json:"actionable_messages"`
	Pending       int     `json:"drafts_pending"`
	Approved      int     `json:"drafts_approved"`
	Dismissed     int     `json:"drafts_dismissed"`
	NeedsReply    int     `json:"drafts_needing_reply"`
	MemberLeft    bool    `json:"member_left"`
}

type calendarIssueRow struct {
	TaskID        string  `json:"task_id"`
	Title         string  `json:"title"`
	HouseholdID   string  `json:"household_id"`
	HouseholdName string  `json:"household_name"`
	OwnerName     string  `json:"owner_name"`
	State         string  `json:"calendar_sync_state"`
	LastError     *string `json:"calendar_last_error"`
	LastSyncedAt  *string `json:"calendar_last_synced_at"`
	DueOn         *string `json:"due_on"`
	EventURL      *string `json:"google_event_url"`
}

type opsResponse struct {
	Mailboxes      []mailboxRow       `json:"mailboxes"`
	CalendarIssues []calendarIssueRow `json:"calendar_issues"`
	DraftFunnel    []funnelRow        `json:"draft_funnel"`
	Totals         map[string]int     `json:"totals"`
	GeneratedAt    string             `json:"generated_at"`
}

type funnelRow struct {
	Label string `json:"label"`
	Count int    `json:"count"`
}

func (a *API) Ops(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	resp := opsResponse{
		Totals:      map[string]int{},
		GeneratedAt: a.now().UTC().Format(time.RFC3339),
	}

	rows, err := a.DB.Query(ctx, `
		select g.member_id::text, m.display_name, g.household_id::text, h.name,
		       g.email, g.client_kind, g.connected_at, g.last_sync_at, g.last_sync_count,
		       (select count(*) from processed_emails p where p.member_id = g.member_id),
		       (select count(*) from processed_emails p
		         where p.member_id = g.member_id and p.actionable),
		       (select count(*) from drafts d where d.source_member_id = g.member_id and d.status = 'pending'),
		       (select count(*) from drafts d where d.source_member_id = g.member_id and d.status = 'approved'),
		       (select count(*) from drafts d where d.source_member_id = g.member_id and d.status = 'dismissed'),
		       (select count(*) from drafts d where d.source_member_id = g.member_id
		          and d.needs_reply and d.reply_status in ('none','drafted')),
		       (m.left_at is not null)
		  from google_accounts g
		  join members m on m.id = g.member_id
		  join households h on h.id = g.household_id
		 order by g.last_sync_at nulls first`)
	if err != nil {
		fail(w, "ops mailboxes", err)
		return
	}
	resp.Mailboxes = []mailboxRow{}
	now := a.now()
	for rows.Next() {
		var mb mailboxRow
		var connected time.Time
		var lastSync *time.Time
		if err := rows.Scan(&mb.MemberID, &mb.MemberName, &mb.HouseholdID, &mb.HouseholdName,
			&mb.Email, &mb.ClientKind, &connected, &lastSync, &mb.LastSyncCount,
			&mb.Scanned, &mb.Actionable, &mb.Pending, &mb.Approved, &mb.Dismissed,
			&mb.NeedsReply, &mb.MemberLeft); err != nil {
			rows.Close()
			fail(w, "scan mailbox", err)
			return
		}
		mb.ConnectedAt = connected.UTC().Format(time.RFC3339)
		mb.LastSyncAt = tsPtr(lastSync)
		if lastSync != nil {
			h := int(now.Sub(*lastSync).Hours())
			mb.StaleHours = &h
		}
		resp.Mailboxes = append(resp.Mailboxes, mb)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fail(w, "iterate mailboxes", err)
		return
	}

	// Every non-healthy calendar state, worst first: retry_required is an error
	// evend will keep hitting, external_deleted is waiting on a human, and
	// external_changed is merely informational.
	rows, err = a.DB.Query(ctx, `
		select t.id::text, t.title, t.household_id::text, h.name, om.display_name,
		       t.calendar_sync_state, t.calendar_last_error, t.calendar_last_synced_at,
		       t.due_on, t.google_event_url
		  from tasks t
		  join households h on h.id = t.household_id
		  join members om on om.id = t.owner_member_id
		 where t.archived_at is null
		   and t.calendar_sync_state in ('retry_required','external_deleted','external_changed')
		 order by case t.calendar_sync_state
		            when 'retry_required' then 0
		            when 'external_deleted' then 1
		            else 2 end,
		          t.calendar_last_synced_at desc nulls last
		 limit 200`)
	if err != nil {
		fail(w, "ops calendar", err)
		return
	}
	resp.CalendarIssues = []calendarIssueRow{}
	for rows.Next() {
		var c calendarIssueRow
		var due, synced *time.Time
		if err := rows.Scan(&c.TaskID, &c.Title, &c.HouseholdID, &c.HouseholdName, &c.OwnerName,
			&c.State, &c.LastError, &synced, &due, &c.EventURL); err != nil {
			rows.Close()
			fail(w, "scan calendar issue", err)
			return
		}
		c.DueOn, c.LastSyncedAt = dateOnly(due), tsPtr(synced)
		resp.CalendarIssues = append(resp.CalendarIssues, c)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fail(w, "iterate calendar issues", err)
		return
	}

	// The funnel is mail → verdict → draft → todo. Each step's drop-off is the
	// classifier's or the household's, and the shape says which.
	funnel := []struct{ label, query string }{
		{"Messages scanned", `select count(*) from processed_emails`},
		{"Judged actionable", `select count(*) from processed_emails where actionable`},
		{"Drafts created", `select count(*) from drafts where gmail_message_id is not null`},
		{"Drafts approved", `select count(*) from drafts where status = 'approved'`},
		{"Became a todo", `select count(*) from drafts where resulting_task_id is not null`},
	}
	resp.DraftFunnel = []funnelRow{}
	for _, f := range funnel {
		var n int
		if err := a.DB.QueryRow(ctx, f.query).Scan(&n); err != nil {
			fail(w, "ops funnel", err)
			return
		}
		resp.DraftFunnel = append(resp.DraftFunnel, funnelRow{Label: f.label, Count: n})
	}

	totals := map[string]string{
		"mailboxes":          `select count(*) from google_accounts`,
		"stale_mailboxes":    `select count(*) from google_accounts where last_sync_at is null or last_sync_at < now() - interval '24 hours'`,
		"retry_required":     `select count(*) from tasks where archived_at is null and calendar_sync_state = 'retry_required'`,
		"external_deleted":   `select count(*) from tasks where archived_at is null and calendar_sync_state = 'external_deleted'`,
		"external_changed":   `select count(*) from tasks where archived_at is null and calendar_sync_state = 'external_changed'`,
		"drafts_pending":     `select count(*) from drafts where status = 'pending'`,
		"drafts_need_reply":  `select count(*) from drafts where needs_reply and reply_status in ('none','drafted')`,
		"households_with_cal": `select count(*) from households where calendar_id is not null and calendar_id <> 'primary'`,
	}
	for key, q := range totals {
		var n int
		if err := a.DB.QueryRow(ctx, q).Scan(&n); err != nil {
			fail(w, "ops total "+key, err)
			return
		}
		resp.Totals[key] = n
	}
	writeJSON(w, http.StatusOK, resp)
}
