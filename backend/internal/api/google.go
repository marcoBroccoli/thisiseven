package api

import (
	"context"
	"encoding/base64"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/claude"
	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// googleAccount is one *member's* connected Google identity. Each member
// connects their own mailbox: the inbox is private, only the Calendar is
// shared, so nothing here is looked up by household alone.
type googleAccount struct {
	MemberID     string
	HouseholdID  string
	Email        string
	RefreshToken string
	ClientKind   string
	LastSyncAt   *time.Time
	LastSync     int
}

const googleAccountCols = `member_id, household_id, email, refresh_token, client_kind,
	last_sync_at, last_sync_count`

func scanGoogleAccount(row pgx.Row) (*googleAccount, error) {
	g := &googleAccount{}
	if err := row.Scan(&g.MemberID, &g.HouseholdID, &g.Email, &g.RefreshToken,
		&g.ClientKind, &g.LastSyncAt, &g.LastSync); err != nil {
		return nil, err
	}
	return g, nil
}

// googleAccountForMember returns the caller's own mailbox connection.
func (a *API) googleAccountForMember(ctx context.Context, memberID string) (*googleAccount, error) {
	return scanGoogleAccount(a.DB.QueryRow(ctx,
		`select `+googleAccountCols+` from google_accounts where member_id = $1`, memberID))
}

// householdGoogleAccounts lists every connected mailbox in a household. Only
// the shared Calendar reads across members — never the inbox.
func (a *API) householdGoogleAccounts(ctx context.Context, householdID string) ([]*googleAccount, error) {
	rows, err := a.DB.Query(ctx,
		`select `+googleAccountCols+` from google_accounts where household_id = $1
		 order by connected_at`, householdID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*googleAccount
	for rows.Next() {
		g, err := scanGoogleAccount(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

// householdCalendarAccount picks the token used for the *shared* Calendar:
// the caller's own connection when they have one, otherwise any connected
// member's. The calendar must keep working when only one partner is connected.
func (a *API) householdCalendarAccount(ctx context.Context, m *Membership) (*googleAccount, error) {
	accounts, err := a.householdGoogleAccounts(ctx, m.HouseholdID)
	if err != nil {
		return nil, err
	}
	if len(accounts) == 0 {
		return nil, pgx.ErrNoRows
	}
	for _, g := range accounts {
		if g.MemberID == m.MemberID {
			return g, nil
		}
	}
	return accounts[0], nil
}

// householdCalendar is the household's own shared calendar id + last sync.
// It lives on the household so it survives the member who created it
// disconnecting their mailbox.
func (a *API) householdCalendar(ctx context.Context, householdID string) (string, *time.Time, error) {
	var id string
	var lastSync *time.Time
	err := a.DB.QueryRow(ctx,
		`select calendar_id, calendar_last_sync_at from households where id = $1`,
		householdID).Scan(&id, &lastSync)
	return id, lastSync, err
}

func (a *API) googleReady(w http.ResponseWriter) bool {
	if !a.Google.Configured() {
		httpx.Error(w, http.StatusConflict, "google_not_configured",
			"the server has no Google OAuth client configured")
		return false
	}
	return true
}

// POST /v1/google/connect {code, redirect_uri, code_verifier?}
func (a *API) GoogleConnect(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !a.googleReady(w) {
		return
	}
	var in struct {
		Code         string `json:"code"`
		RedirectURI  string `json:"redirect_uri"`
		CodeVerifier string `json:"code_verifier"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	if in.Code == "" || in.RedirectURI == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_fields", "code and redirect_uri are required")
		return
	}
	refresh, email, clientKind, err := a.Google.ExchangeCode(r.Context(), in.Code, in.RedirectURI, in.CodeVerifier)
	if err != nil {
		slog.Error("google connect", "err", err)
		httpx.Error(w, http.StatusBadGateway, "google_exchange_failed",
			"Google did not accept the authorization code")
		return
	}
	_, err = a.DB.Exec(r.Context(), `
		insert into google_accounts (household_id, member_id, email, refresh_token, client_kind, connected_by)
		values ($1, $2, $3, $4, $5, $2)
		on conflict (member_id) do update set
			household_id = excluded.household_id,
			email = excluded.email,
			refresh_token = excluded.refresh_token,
			client_kind = excluded.client_kind,
			connected_at = now()`,
		m.HouseholdID, m.MemberID, email, refresh, clientKind)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store the connection")
		return
	}
	a.Google.Forget(m.MemberID)
	a.GoogleStatus(w, r)
}

// partnerConnected reports whether the *other* member has a mailbox of their
// own. Only the boolean crosses the member boundary — never their address.
func (a *API) partnerConnected(ctx context.Context, m *Membership) bool {
	if !m.HasPartner() {
		return false
	}
	var exists bool
	if err := a.DB.QueryRow(ctx,
		`select exists(select 1 from google_accounts where member_id = $1)`,
		m.PartnerID).Scan(&exists); err != nil {
		return false
	}
	return exists
}

// GET /v1/google/status — the caller's own connection, plus whether their
// partner has connected theirs (so the app can explain the shared calendar).
func (a *API) GoogleStatus(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	out := map[string]any{"partner_connected": a.partnerConnected(r.Context(), m)}
	if _, lastCalendarSync, err := a.householdCalendar(r.Context(), m.HouseholdID); err == nil && lastCalendarSync != nil {
		out["calendar_last_sync_at"] = lastCalendarSync.UTC().Format(time.RFC3339)
	}
	g, err := a.googleAccountForMember(r.Context(), m.MemberID)
	if errors.Is(err, pgx.ErrNoRows) {
		out["connected"] = false
		httpx.JSON(w, http.StatusOK, out)
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "status lookup failed")
		return
	}
	out["connected"] = true
	out["email"] = g.Email
	out["last_sync_count"] = g.LastSync
	if g.LastSyncAt != nil {
		out["last_sync_at"] = g.LastSyncAt.UTC().Format(time.RFC3339)
	}
	job := a.jobSnapshot(m.MemberID)
	out["sync_running"] = job.Running
	out["scanned"] = job.Scanned
	out["classified"] = job.Classified
	out["created"] = job.Created
	out["has_more"] = job.HasMore
	httpx.JSON(w, http.StatusOK, out)
}

// POST /v1/google/disconnect — only the caller's own mailbox. Drafts already
// discovered stay; they simply stop being refreshed.
func (a *API) GoogleDisconnect(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	_, err := a.DB.Exec(r.Context(),
		`delete from google_accounts where member_id = $1`, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not disconnect")
		return
	}
	a.Google.Forget(m.MemberID)
	httpx.JSON(w, http.StatusOK, map[string]any{
		"connected":         false,
		"partner_connected": a.partnerConnected(r.Context(), m),
	})
}

// POST /v1/google/sync — start (or join) an async scan-and-classify job.
// The app polls GET /v1/google/status + /v1/drafts while it runs, so the
// inbox fills batch by batch.
func (a *API) GoogleSync(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !a.googleReady(w) {
		return
	}
	if _, err := a.googleAccountForMember(r.Context(), m.MemberID); errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusConflict, "not_connected", "connect your Google account first")
		return
	} else if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "account lookup failed")
		return
	}
	if !a.claimSync(m.MemberID) {
		httpx.Error(w, http.StatusConflict, "sync_running", "a scan is already in progress")
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
		defer cancel()
		a.runSync(ctx, m.MemberID)
	}()
	httpx.JSON(w, http.StatusAccepted, map[string]any{"started": true})
}

// syncJob is the in-memory progress of one member's scan. Counters are
// updated after every classification batch so status polling sees the inbox
// grow live.
type syncJob struct {
	Running    bool
	Scanned    int
	Classified int
	Created    int
	HasMore    bool
	Err        string
}

func (a *API) jobSnapshot(memberID string) syncJob {
	a.syncMu.Lock()
	defer a.syncMu.Unlock()
	if j, ok := a.syncJobs[memberID]; ok {
		return *j
	}
	return syncJob{}
}

// claimSync flips the member into a running job; false when one is live.
func (a *API) claimSync(memberID string) bool {
	a.syncMu.Lock()
	defer a.syncMu.Unlock()
	if a.syncJobs == nil {
		a.syncJobs = map[string]*syncJob{}
	}
	if j, ok := a.syncJobs[memberID]; ok && j.Running {
		return false
	}
	a.syncJobs[memberID] = &syncJob{Running: true}
	return true
}

func (a *API) updateJob(memberID string, mut func(*syncJob)) {
	a.syncMu.Lock()
	defer a.syncMu.Unlock()
	if j, ok := a.syncJobs[memberID]; ok {
		mut(j)
	}
}

const (
	syncListWindow = 100 // ids listed from Gmail per run
	syncTakePerRun = 25  // emails fetched + classified per run ("read more" continues)
	classifyBatch  = 10  // emails per Claude call
)

// runSync executes one claimed scan job end to end. Callers must have
// claimSync'd first. A job belongs to one member's mailbox.
func (a *API) runSync(ctx context.Context, memberID string) {
	err := a.runSyncInner(ctx, memberID)
	a.updateJob(memberID, func(j *syncJob) {
		j.Running = false
		if err != nil {
			j.Err = err.Error()
		}
	})
	if err != nil {
		slog.Error("google sync", "member", memberID, "err", err)
	}
}

func (a *API) runSyncInner(ctx context.Context, memberID string) error {
	g, err := a.googleAccountForMember(ctx, memberID)
	if err != nil {
		return err
	}
	token, err := a.Google.AccessToken(ctx, memberID, g.RefreshToken, g.ClientKind)
	if errors.Is(err, google.ErrInvalidGrant) {
		_, _ = a.DB.Exec(ctx, `delete from google_accounts where member_id = $1`, memberID)
		a.Google.Forget(memberID)
		return err
	}
	if err != nil {
		return err
	}

	ids, err := a.Google.ListHouseholdMessages(ctx, token, syncListWindow)
	if err != nil {
		return err
	}

	// Drop everything this member's mailbox already classified or drafted. The
	// partner's verdicts are deliberately not consulted: their mailbox is a
	// different stream of mail.
	seen := map[string]bool{}
	rows, err := a.DB.Query(ctx, `
		select gmail_message_id from processed_emails where member_id = $1
		union
		select gmail_message_id from drafts where source_member_id = $1 and gmail_message_id is not null`,
		memberID)
	if err != nil {
		return err
	}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			seen[id] = true
		}
	}
	rows.Close()

	var unprocessed []string
	for _, id := range ids {
		if !seen[id] {
			unprocessed = append(unprocessed, id)
		}
	}
	take := unprocessed
	if len(take) > syncTakePerRun {
		take = take[:syncTakePerRun]
	}
	hasMore := len(unprocessed) > len(take)
	a.updateJob(memberID, func(j *syncJob) {
		j.Scanned = len(take)
		j.HasMore = hasMore
	})

	created := 0
	for i := 0; i < len(take); i += classifyBatch {
		end := i + classifyBatch
		if end > len(take) {
			end = len(take)
		}
		// Mail found in a member's own mailbox lands on them by default;
		// handing it to the partner stays a review-sheet decision.
		n, err := a.classifyAndInsert(ctx, g.HouseholdID, memberID, token, take[i:end])
		if err != nil {
			return err
		}
		created += n
		a.updateJob(memberID, func(j *syncJob) {
			j.Classified = end
			j.Created = created
		})
	}

	_, err = a.DB.Exec(ctx, `
		update google_accounts set last_sync_at = now(), last_sync_count = $1
		where member_id = $2`, created, memberID)
	return err
}

// classifyAndInsert fetches one batch's metadata, runs the Claude classifier
// (heuristic fallback), inserts actionable drafts, and records every verdict
// in processed_emails so nothing is ever re-classified.
func (a *API) classifyAndInsert(ctx context.Context, householdID, memberID, token string, ids []string) (created int, err error) {
	type meta struct {
		id  string
		msg *google.Message
	}
	var metas []meta
	for _, id := range ids {
		msg, err := a.Google.MessageMeta(ctx, token, id)
		if err != nil {
			return created, err
		}
		if strings.TrimSpace(msg.Subject) == "" {
			if _, err := a.DB.Exec(ctx, `
				insert into processed_emails (household_id, member_id, gmail_message_id, actionable)
				values ($1, $2, $3, false) on conflict do nothing`, householdID, memberID, id); err != nil {
				return created, err
			}
			continue
		}
		metas = append(metas, meta{id, msg})
	}
	if len(metas) == 0 {
		return created, nil
	}

	today := time.Now().In(Amsterdam).Format("2006-01-02")

	// Existing pending titles give the classifier dedupe context.
	var pending []string
	rows, err := a.DB.Query(ctx, `
		select title from drafts where source_member_id = $1 and status = 'pending'
		order by created_at desc limit 50`, memberID)
	if err != nil {
		return created, err
	}
	for rows.Next() {
		var t string
		if rows.Scan(&t) == nil {
			pending = append(pending, t)
		}
	}
	rows.Close()

	verdicts := map[string]claude.Verdict{}
	if a.Claude.Configured() {
		inputs := make([]claude.EmailInput, 0, len(metas))
		for _, m := range metas {
			inputs = append(inputs, claude.EmailInput{
				ID: m.id, From: m.msg.From, Subject: m.msg.Subject,
				Snippet: m.msg.Snippet, Date: m.msg.Date.Format("2006-01-02"),
			})
		}
		out, err := a.Claude.Classify(ctx, inputs, pending, today)
		if err != nil {
			slog.Error("claude classify — falling back to heuristics", "err", err)
		} else {
			for _, v := range out {
				verdicts[v.ID] = v
			}
		}
	}

	for _, m := range metas {
		v, classified := verdicts[m.id]
		if !classified {
			// Heuristic fallback: everything becomes a draft, raw wording.
			ex := google.Extract(m.msg.Subject, m.msg.Snippet, m.msg.From, time.Now().In(Amsterdam))
			v = claude.Verdict{
				ID: m.id, Actionable: true,
				Title: ex.Title, Urgency: ex.Urgency, AmountCents: ex.AmountCents,
				NeedsReply:     google.NeedsReply(m.msg.Subject, m.msg.Snippet, m.msg.From),
				SuggestedReply: google.SuggestedReply(m.msg.Subject, m.msg.Snippet, m.msg.From),
			}
			if ex.DueOn != nil {
				d := ex.DueOn.Format("2006-01-02")
				v.DueOn = &d
			}
		}
		// A title that survived the corrective pass still echoing the raw
		// subject gets a plain verb prefix rather than raw wording.
		if classified && v.Actionable && claude.EchoesSubject(v.Title, m.msg.Subject) {
			v.Title = "Sort out: " + strings.TrimSpace(m.msg.Subject)
		}
		if err := a.insertVerdict(ctx, householdID, memberID, m.id, m.msg, v); err != nil {
			return created, err
		}
		if v.Actionable && v.DuplicateOf == nil {
			created++
		}
	}
	return created, nil
}

func (a *API) insertVerdict(ctx context.Context, householdID, memberID, gmailID string, msg *google.Message, v claude.Verdict) error {
	tx, err := a.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	actionable := v.Actionable && v.DuplicateOf == nil
	var note *string
	if v.DuplicateOf != nil {
		n := "dup_of:" + *v.DuplicateOf
		note = &n
	}
	if _, err := tx.Exec(ctx, `
		insert into processed_emails (household_id, member_id, gmail_message_id, actionable, note)
		values ($1, $2, $3, $4, $5) on conflict do nothing`, householdID, memberID, gmailID, actionable, note); err != nil {
		return err
	}
	if actionable {
		title := strings.TrimSpace(v.Title)
		if title == "" {
			title = msg.Subject
		}
		var summary *string
		if s := strings.TrimSpace(v.Summary); s != "" {
			summary = &s
		}
		var dueOn *time.Time
		if v.DueOn != nil {
			if d, err := time.Parse("2006-01-02", *v.DueOn); err == nil {
				dueOn = &d
			}
		}
		urgency := v.Urgency
		if urgency < 1 || urgency > 3 {
			urgency = 1
		}
		var amount *int64
		if v.AmountCents != nil && *v.AmountCents > 0 {
			amount = v.AmountCents
		}
		reminder := "1_day"
		if dueOn != nil {
			reminder = "3_days"
		}
		preview := msg.Snippet
		if r := []rune(preview); len(r) > 240 {
			preview = string(r[:240])
		}
		var previewPtr *string
		if preview != "" {
			previewPtr = &preview
		}
		category := v.Category
		switch category {
		case "bills", "appointments", "subscriptions", "admin", "other":
		default:
			category = "other"
		}
		needsReply := v.NeedsReply && google.CanReply(msg.From)
		var suggestedReply *string
		if needsReply {
			s := strings.TrimSpace(v.SuggestedReply)
			if s == "" {
				s = google.SuggestedReply(msg.Subject, msg.Snippet, msg.From)
			}
			if s != "" {
				suggestedReply = &s
			}
		}
		if _, err := tx.Exec(ctx, `
			insert into drafts (household_id, from_label, subject, summary, urgency,
				title, owner_member_id, amount_cents, due_on, reminder, created_by,
				source_member_id, gmail_message_id, source_from, source_preview, category,
				needs_reply, suggested_reply)
			values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $7, $7, $11, $12, $13, $14, $15, $16)
			on conflict do nothing`,
			householdID, google.SenderDisplay(msg.From), msg.Subject, summary,
			urgency, title, memberID, amount, dueOn, reminder,
			gmailID, msg.From, previewPtr, category, needsReply, suggestedReply); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// RunGmailPoller re-scans every connected mailbox on the interval until ctx
// ends. One member connecting never pulls their partner's mail — each account
// is its own pass. Started from main when the Google client is configured.
func (a *API) RunGmailPoller(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			rows, err := a.DB.Query(ctx, `select member_id from google_accounts`)
			if err != nil {
				slog.Error("gmail poller list", "err", err)
				continue
			}
			var members []string
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					members = append(members, id)
				}
			}
			rows.Close()
			for _, id := range members {
				if !a.claimSync(id) {
					continue
				}
				syncCtx, cancel := context.WithTimeout(ctx, 4*time.Minute)
				a.runSync(syncCtx, id)
				cancel()
				if job := a.jobSnapshot(id); job.Created > 0 {
					slog.Info("gmail poller", "member", id, "created", job.Created, "scanned", job.Scanned)
				}
			}
		}
	}
}

// publishTaskToCalendar writes a Calendar event for a dated todo. It runs
// after the database write, so a Google failure never loses household work.
func (a *API) publishTaskToCalendar(ctx context.Context, m *Membership,
	taskID, title, fromLabel string, amountCents *int64, dueOn *time.Time, reminder string) (calendarError string) {
	if dueOn == nil || !a.Google.Configured() {
		return ""
	}
	// The calendar is the household's, so any connected member's token can
	// write it — a partner who has not connected still gets their dated todos
	// on the shared calendar.
	g, err := a.householdCalendarAccount(ctx, m)
	if errors.Is(err, pgx.ErrNoRows) {
		return ""
	}
	if err != nil {
		return a.recordCalendarFailure(ctx, taskID, "calendar lookup failed")
	}
	current, _, err := a.householdCalendar(ctx, m.HouseholdID)
	if err != nil {
		return a.recordCalendarFailure(ctx, taskID, "calendar lookup failed")
	}
	token, err := a.Google.AccessToken(ctx, g.MemberID, g.RefreshToken, g.ClientKind)
	if err != nil {
		slog.Error("calendar token", "err", err)
		return a.recordCalendarFailure(ctx, taskID, "Google access expired — reconnect to write calendar events")
	}
	calID, err := a.ensureHouseholdCalendar(ctx, m, token, current)
	if err != nil {
		slog.Error("calendar create", "err", err)
		return a.recordCalendarFailure(ctx, taskID, "the shared calendar could not be created")
	}
	var existingEventID *string
	var recurrence string
	var recurrenceUntil *time.Time
	var recurrenceCount *int
	if err := a.DB.QueryRow(ctx, `
		select google_event_id, recurrence, recurrence_until, recurrence_count
		from tasks where id = $1`, taskID).
		Scan(&existingEventID, &recurrence, &recurrenceUntil, &recurrenceCount); err != nil {
		return a.recordCalendarFailure(ctx, taskID, "the todo could not be prepared for Calendar")
	}
	payload := google.BuildEvent(title, fromLabel, amountCents, *dueOn, reminder)
	payload.Recurrence = google.RecurrenceRule(recurrence, recurrenceUntil, recurrenceCount)
	payload.ExtendedProperties = &google.EventExtendedProperties{
		Private: map[string]string{"evenTaskId": taskID},
	}
	var eventID, url string
	if existingEventID != nil && *existingEventID != "" {
		eventID, url, err = a.Google.UpdateEvent(ctx, token, calID, *existingEventID, payload)
	} else {
		eventID, url, err = a.Google.InsertEvent(ctx, token, calID, payload)
	}
	if err != nil {
		slog.Error("calendar publish", "err", err)
		return a.recordCalendarFailure(ctx, taskID, "the calendar event could not be updated")
	}
	if _, err := a.DB.Exec(ctx, `
		update tasks set google_event_id = $1, google_event_url = $2,
			calendar_sync_state = 'synced', calendar_last_synced_at = now(), calendar_last_error = null
		where id = $3`,
		eventID, url, taskID); err != nil {
		return "the event was created but could not be recorded"
	}
	return ""
}

func (a *API) recordCalendarFailure(ctx context.Context, taskID, message string) string {
	_, _ = a.DB.Exec(ctx, `
		update tasks set calendar_sync_state = 'retry_required', calendar_last_error = $1
		where id = $2`, message, taskID)
	return message
}

// clearTaskCalendarMapping records that a todo is no longer dated. It runs
// after the remote event has been removed (or when no event existed), so an
// undated todo cannot remain falsely represented as a Calendar item.
func (a *API) clearTaskCalendarMapping(ctx context.Context, taskID string) error {
	_, err := a.DB.Exec(ctx, `
		update tasks set google_event_id = null, google_event_url = null,
			calendar_sync_state = 'not_scheduled', calendar_last_synced_at = now(),
			calendar_last_error = null
		where id = $1`, taskID)
	return err
}

// removeTaskFromCalendar clears an event mapping only after the remote delete
// succeeds. The task keeps retry_required when Google cannot confirm removal.
func (a *API) removeTaskFromCalendar(ctx context.Context, m *Membership, taskID string, eventID *string) string {
	if eventID != nil && *eventID != "" {
		if err := a.deleteTaskCalendarEvent(ctx, m, *eventID); err != nil {
			return a.recordCalendarFailure(ctx, taskID, "the calendar event could not be removed")
		}
	}
	if err := a.clearTaskCalendarMapping(ctx, taskID); err != nil {
		return a.recordCalendarFailure(ctx, taskID, "the Calendar mapping could not be cleared")
	}
	return ""
}

// deleteTaskCalendarEvent removes a previously-published event after the
// local todo is archived. The local delete wins if Google is temporarily
// unavailable, avoiding a blocked capture workflow.
func (a *API) deleteTaskCalendarEvent(ctx context.Context, m *Membership, eventID string) error {
	if eventID == "" || !a.Google.Configured() {
		return nil
	}
	calID, _, err := a.householdCalendar(ctx, m.HouseholdID)
	if err != nil || calID == "" || calID == "primary" {
		return nil
	}
	g, err := a.householdCalendarAccount(ctx, m)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	token, err := a.Google.AccessToken(ctx, g.MemberID, g.RefreshToken, g.ClientKind)
	if err != nil {
		return err
	}
	return a.Google.DeleteEvent(ctx, token, calID, eventID)
}

// ensureHouseholdCalendar lazily creates the shared "Even — <household>"
// calendar the first time an event is written, so approvals never land on
// anyone's personal primary calendar.
func (a *API) ensureHouseholdCalendar(ctx context.Context, m *Membership, token, current string) (string, error) {
	if current != "" && current != "primary" {
		return current, nil
	}
	id, err := a.Google.CreateCalendar(ctx, token, "Even — "+m.Household)
	if err != nil {
		return "", err
	}
	if _, err := a.DB.Exec(ctx, `
		update households set calendar_id = $1 where id = $2`,
		id, m.HouseholdID); err != nil {
		return "", err
	}
	return id, nil
}

// GoogleCalendarInfo exposes the shared calendar so the partner can add it
// in their own Google Calendar ("add by calendar id" link).
func (a *API) GoogleCalendarInfo(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if _, err := a.householdCalendarAccount(r.Context(), m); errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusConflict, "not_connected", "connect Google first")
		return
	} else if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "calendar lookup failed")
		return
	}
	calID, _, err := a.householdCalendar(r.Context(), m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "calendar lookup failed")
		return
	}
	out := map[string]any{
		"calendar_id": calID,
		"shared":      calID != "primary",
	}
	if calID != "primary" {
		cid := base64.RawURLEncoding.EncodeToString([]byte(calID))
		out["share_url"] = "https://calendar.google.com/calendar/r?cid=" + cid
	}
	httpx.JSON(w, http.StatusOK, out)
}
