package api

import (
	"context"
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

// googleAccount is one household's connected Google identity.
type googleAccount struct {
	Email        string
	RefreshToken string
	ClientKind   string
	ConnectedBy  *string
	CalendarID   string
	LastSyncAt   *time.Time
	LastSync     int
}

func (a *API) googleAccount(ctx context.Context, householdID string) (*googleAccount, error) {
	g := &googleAccount{}
	err := a.DB.QueryRow(ctx, `
		select email, refresh_token, client_kind, connected_by, calendar_id, last_sync_at, last_sync_count
		from google_accounts where household_id = $1`, householdID).
		Scan(&g.Email, &g.RefreshToken, &g.ClientKind, &g.ConnectedBy, &g.CalendarID, &g.LastSyncAt, &g.LastSync)
	if err != nil {
		return nil, err
	}
	return g, nil
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
		insert into google_accounts (household_id, email, refresh_token, client_kind, connected_by)
		values ($1, $2, $3, $4, $5)
		on conflict (household_id) do update set
			email = excluded.email,
			refresh_token = excluded.refresh_token,
			client_kind = excluded.client_kind,
			connected_by = excluded.connected_by,
			connected_at = now()`,
		m.HouseholdID, email, refresh, clientKind, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not store the connection")
		return
	}
	a.Google.Forget(m.HouseholdID)
	a.GoogleStatus(w, r)
}

// GET /v1/google/status
func (a *API) GoogleStatus(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	g, err := a.googleAccount(r.Context(), m.HouseholdID)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.JSON(w, http.StatusOK, map[string]any{"connected": false})
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "status lookup failed")
		return
	}
	out := map[string]any{
		"connected":       true,
		"email":           g.Email,
		"last_sync_count": g.LastSync,
	}
	if g.LastSyncAt != nil {
		out["last_sync_at"] = g.LastSyncAt.UTC().Format(time.RFC3339)
	}
	job := a.jobSnapshot(m.HouseholdID)
	out["sync_running"] = job.Running
	out["scanned"] = job.Scanned
	out["classified"] = job.Classified
	out["created"] = job.Created
	out["has_more"] = job.HasMore
	httpx.JSON(w, http.StatusOK, out)
}

// POST /v1/google/disconnect
func (a *API) GoogleDisconnect(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	_, err := a.DB.Exec(r.Context(),
		`delete from google_accounts where household_id = $1`, m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not disconnect")
		return
	}
	a.Google.Forget(m.HouseholdID)
	httpx.JSON(w, http.StatusOK, map[string]any{"connected": false})
}

// POST /v1/google/sync — start (or join) an async scan-and-classify job.
// The app polls GET /v1/google/status + /v1/drafts while it runs, so the
// inbox fills batch by batch.
func (a *API) GoogleSync(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !a.googleReady(w) {
		return
	}
	if _, err := a.googleAccount(r.Context(), m.HouseholdID); errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusConflict, "not_connected", "connect the household Google account first")
		return
	} else if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "account lookup failed")
		return
	}
	if !a.claimSync(m.HouseholdID) {
		httpx.Error(w, http.StatusConflict, "sync_running", "a scan is already in progress")
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
		defer cancel()
		a.runSync(ctx, m.HouseholdID)
	}()
	httpx.JSON(w, http.StatusAccepted, map[string]any{"started": true})
}

// syncJob is the in-memory progress of one household's scan. Counters are
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

func (a *API) jobSnapshot(householdID string) syncJob {
	a.syncMu.Lock()
	defer a.syncMu.Unlock()
	if j, ok := a.syncJobs[householdID]; ok {
		return *j
	}
	return syncJob{}
}

// claimSync flips the household into a running job; false when one is live.
func (a *API) claimSync(householdID string) bool {
	a.syncMu.Lock()
	defer a.syncMu.Unlock()
	if a.syncJobs == nil {
		a.syncJobs = map[string]*syncJob{}
	}
	if j, ok := a.syncJobs[householdID]; ok && j.Running {
		return false
	}
	a.syncJobs[householdID] = &syncJob{Running: true}
	return true
}

func (a *API) updateJob(householdID string, mut func(*syncJob)) {
	a.syncMu.Lock()
	defer a.syncMu.Unlock()
	if j, ok := a.syncJobs[householdID]; ok {
		mut(j)
	}
}

const (
	syncListWindow = 100 // ids listed from Gmail per run
	syncTakePerRun = 25  // emails fetched + classified per run ("read more" continues)
	classifyBatch  = 10  // emails per Claude call
)

// runSync executes one claimed scan job end to end. Callers must have
// claimSync'd first.
func (a *API) runSync(ctx context.Context, householdID string) {
	err := a.runSyncInner(ctx, householdID)
	a.updateJob(householdID, func(j *syncJob) {
		j.Running = false
		if err != nil {
			j.Err = err.Error()
		}
	})
	if err != nil {
		slog.Error("google sync", "household", householdID, "err", err)
	}
}

func (a *API) runSyncInner(ctx context.Context, householdID string) error {
	g, err := a.googleAccount(ctx, householdID)
	if err != nil {
		return err
	}
	token, err := a.Google.AccessToken(ctx, householdID, g.RefreshToken, g.ClientKind)
	if errors.Is(err, google.ErrInvalidGrant) {
		_, _ = a.DB.Exec(ctx, `delete from google_accounts where household_id = $1`, householdID)
		a.Google.Forget(householdID)
		return err
	}
	if err != nil {
		return err
	}

	ids, err := a.Google.ListHouseholdMessages(ctx, token, syncListWindow)
	if err != nil {
		return err
	}

	// Drop everything already classified or already a draft.
	seen := map[string]bool{}
	rows, err := a.DB.Query(ctx, `
		select gmail_message_id from processed_emails where household_id = $1
		union
		select gmail_message_id from drafts where household_id = $1 and gmail_message_id is not null`,
		householdID)
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
	a.updateJob(householdID, func(j *syncJob) {
		j.Scanned = len(take)
		j.HasMore = hasMore
	})

	// Default owner: whoever connected, else the household's first member.
	owner := ""
	if g.ConnectedBy != nil {
		owner = *g.ConnectedBy
	} else if err := a.DB.QueryRow(ctx, `
		select id from members where household_id = $1 order by created_at limit 1`,
		householdID).Scan(&owner); err != nil {
		return err
	}

	created := 0
	for i := 0; i < len(take); i += classifyBatch {
		end := i + classifyBatch
		if end > len(take) {
			end = len(take)
		}
		n, err := a.classifyAndInsert(ctx, householdID, owner, token, take[i:end])
		if err != nil {
			return err
		}
		created += n
		a.updateJob(householdID, func(j *syncJob) {
			j.Classified = end
			j.Created = created
		})
	}

	_, err = a.DB.Exec(ctx, `
		update google_accounts set last_sync_at = now(), last_sync_count = $1
		where household_id = $2`, created, householdID)
	return err
}

// classifyAndInsert fetches one batch's metadata, runs the Claude classifier
// (heuristic fallback), inserts actionable drafts, and records every verdict
// in processed_emails so nothing is ever re-classified.
func (a *API) classifyAndInsert(ctx context.Context, householdID, owner, token string, ids []string) (created int, err error) {
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
				insert into processed_emails (household_id, gmail_message_id, actionable)
				values ($1, $2, false) on conflict do nothing`, householdID, id); err != nil {
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
	verdicts := map[string]claude.Verdict{}
	if a.Claude.Configured() {
		inputs := make([]claude.EmailInput, 0, len(metas))
		for _, m := range metas {
			inputs = append(inputs, claude.EmailInput{
				ID: m.id, From: m.msg.From, Subject: m.msg.Subject,
				Snippet: m.msg.Snippet, Date: m.msg.Date.Format("2006-01-02"),
			})
		}
		out, err := a.Claude.Classify(ctx, inputs, today)
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
			}
			if ex.DueOn != nil {
				d := ex.DueOn.Format("2006-01-02")
				v.DueOn = &d
			}
		}
		if err := a.insertVerdict(ctx, householdID, owner, m.id, m.msg, v); err != nil {
			return created, err
		}
		if v.Actionable {
			created++
		}
	}
	return created, nil
}

func (a *API) insertVerdict(ctx context.Context, householdID, owner, gmailID string, msg *google.Message, v claude.Verdict) error {
	tx, err := a.DB.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `
		insert into processed_emails (household_id, gmail_message_id, actionable)
		values ($1, $2, $3) on conflict do nothing`, householdID, gmailID, v.Actionable); err != nil {
		return err
	}
	if v.Actionable {
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
		if _, err := tx.Exec(ctx, `
			insert into drafts (household_id, from_label, subject, summary, urgency,
				title, owner_member_id, amount_cents, due_on, reminder, created_by,
				gmail_message_id, source_from, source_preview)
			values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $7, $11, $12, $13)
			on conflict do nothing`,
			householdID, google.SenderDisplay(msg.From), msg.Subject, summary,
			urgency, title, owner, amount, dueOn, reminder,
			gmailID, msg.From, previewPtr); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

// RunGmailPoller re-scans every connected household on the interval until ctx
// ends. Started from main when the Google client is configured.
func (a *API) RunGmailPoller(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			rows, err := a.DB.Query(ctx, `select household_id from google_accounts`)
			if err != nil {
				slog.Error("gmail poller list", "err", err)
				continue
			}
			var households []string
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					households = append(households, id)
				}
			}
			rows.Close()
			for _, id := range households {
				if !a.claimSync(id) {
					continue
				}
				syncCtx, cancel := context.WithTimeout(ctx, 4*time.Minute)
				a.runSync(syncCtx, id)
				cancel()
				if job := a.jobSnapshot(id); job.Created > 0 {
					slog.Info("gmail poller", "household", id, "created", job.Created, "scanned", job.Scanned)
				}
			}
		}
	}
}

// calendarEventForApproval writes the Calendar event for a freshly-approved
// draft's task. Called AFTER the approve transaction commits — a Calendar
// failure never rolls back an approval.
func (a *API) calendarEventForApproval(ctx context.Context, m *Membership,
	taskID, title, fromLabel string, amountCents *int64, dueOn *time.Time, reminder string) (calendarError string) {
	if dueOn == nil || !a.Google.Configured() {
		return ""
	}
	g, err := a.googleAccount(ctx, m.HouseholdID)
	if errors.Is(err, pgx.ErrNoRows) {
		return ""
	}
	if err != nil {
		return "calendar lookup failed"
	}
	token, err := a.Google.AccessToken(ctx, m.HouseholdID, g.RefreshToken, g.ClientKind)
	if err != nil {
		slog.Error("calendar token", "err", err)
		return "Google access expired — reconnect to write calendar events"
	}
	payload := google.BuildEvent(title, fromLabel, amountCents, *dueOn, reminder)
	eventID, url, err := a.Google.InsertEvent(ctx, token, g.CalendarID, payload)
	if err != nil {
		slog.Error("calendar insert", "err", err)
		return "the calendar event could not be created"
	}
	if _, err := a.DB.Exec(ctx, `
		update tasks set google_event_id = $1, google_event_url = $2 where id = $3`,
		eventID, url, taskID); err != nil {
		return "the event was created but could not be recorded"
	}
	return ""
}
