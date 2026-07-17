package api

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// googleAccount is one household's connected Google identity.
type googleAccount struct {
	Email        string
	RefreshToken string
	ConnectedBy  *string
	CalendarID   string
	LastSyncAt   *time.Time
	LastSync     int
}

func (a *API) googleAccount(ctx context.Context, householdID string) (*googleAccount, error) {
	g := &googleAccount{}
	err := a.DB.QueryRow(ctx, `
		select email, refresh_token, connected_by, calendar_id, last_sync_at, last_sync_count
		from google_accounts where household_id = $1`, householdID).
		Scan(&g.Email, &g.RefreshToken, &g.ConnectedBy, &g.CalendarID, &g.LastSyncAt, &g.LastSync)
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
	refresh, email, err := a.Google.ExchangeCode(r.Context(), in.Code, in.RedirectURI, in.CodeVerifier)
	if err != nil {
		slog.Error("google connect", "err", err)
		httpx.Error(w, http.StatusBadGateway, "google_exchange_failed",
			"Google did not accept the authorization code")
		return
	}
	_, err = a.DB.Exec(r.Context(), `
		insert into google_accounts (household_id, email, refresh_token, connected_by)
		values ($1, $2, $3, $4)
		on conflict (household_id) do update set
			email = excluded.email,
			refresh_token = excluded.refresh_token,
			connected_by = excluded.connected_by,
			connected_at = now()`,
		m.HouseholdID, email, refresh, m.MemberID)
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

// POST /v1/google/sync — manual "scan now".
func (a *API) GoogleSync(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !a.googleReady(w) {
		return
	}
	res, err := a.syncHousehold(r.Context(), m.HouseholdID)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusConflict, "not_connected", "connect the household Google account first")
		return
	}
	if errors.Is(err, google.ErrInvalidGrant) {
		httpx.Error(w, http.StatusConflict, "reconnect_required",
			"Google access expired — reconnect the household account")
		return
	}
	if err != nil {
		slog.Error("google sync", "err", err)
		httpx.Error(w, http.StatusBadGateway, "google_sync_failed", "Gmail could not be scanned")
		return
	}
	httpx.JSON(w, http.StatusOK, res)
}

type syncResult struct {
	Scanned int `json:"scanned"`
	Created int `json:"created"`
	Skipped int `json:"skipped"`
}

// syncHousehold scans Gmail into pending drafts. Used by the manual endpoint
// and the background ticker.
func (a *API) syncHousehold(ctx context.Context, householdID string) (*syncResult, error) {
	g, err := a.googleAccount(ctx, householdID)
	if err != nil {
		return nil, err
	}
	token, err := a.Google.AccessToken(ctx, householdID, g.RefreshToken)
	if errors.Is(err, google.ErrInvalidGrant) {
		// Dead refresh token: force an explicit reconnect, stop the ticker noise.
		_, _ = a.DB.Exec(ctx, `delete from google_accounts where household_id = $1`, householdID)
		a.Google.Forget(householdID)
		return nil, err
	}
	if err != nil {
		return nil, err
	}

	ids, err := a.Google.ListHouseholdMessages(ctx, token, 25)
	if err != nil {
		return nil, err
	}

	// Default owner: the member who connected the account, else any member.
	owner := ""
	if g.ConnectedBy != nil {
		owner = *g.ConnectedBy
	} else if err := a.DB.QueryRow(ctx, `
		select id from members where household_id = $1 order by created_at limit 1`,
		householdID).Scan(&owner); err != nil {
		return nil, err
	}

	res := &syncResult{Scanned: len(ids)}
	for _, id := range ids {
		var exists bool
		if err := a.DB.QueryRow(ctx, `
			select exists(select 1 from drafts where household_id = $1 and gmail_message_id = $2)`,
			householdID, id).Scan(&exists); err != nil {
			return nil, err
		}
		if exists {
			res.Skipped++
			continue
		}
		msg, err := a.Google.MessageMeta(ctx, token, id)
		if err != nil {
			return nil, err
		}
		if strings.TrimSpace(msg.Subject) == "" {
			res.Skipped++
			continue
		}
		ex := google.Extract(msg.Subject, msg.Snippet, msg.From, time.Now().In(Amsterdam))
		reminder := "1_day"
		if ex.DueOn != nil {
			reminder = "3_days"
		}
		var summary *string
		if msg.Snippet != "" {
			// Truncate by runes — a byte slice can split a multi-byte
			// UTF-8 character and Postgres rejects the invalid tail.
			s := msg.Snippet
			if r := []rune(s); len(r) > 240 {
				s = string(r[:240])
			}
			summary = &s
		}
		_, err = a.DB.Exec(ctx, `
			insert into drafts (household_id, from_label, subject, summary, urgency,
				title, owner_member_id, amount_cents, due_on, reminder, created_by,
				gmail_message_id, source_from, source_preview)
			values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $7, $11, $12, $4)
			on conflict do nothing`,
			householdID, google.SenderDisplay(msg.From), msg.Subject, summary,
			ex.Urgency, ex.Title, owner, ex.AmountCents, ex.DueOn, reminder,
			id, msg.From)
		if err != nil {
			return nil, err
		}
		res.Created++
	}
	_, err = a.DB.Exec(ctx, `
		update google_accounts set last_sync_at = now(), last_sync_count = $1
		where household_id = $2`, res.Created, householdID)
	return res, err
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
				syncCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
				if res, err := a.syncHousehold(syncCtx, id); err != nil {
					slog.Error("gmail poller sync", "household", id, "err", err)
				} else if res.Created > 0 {
					slog.Info("gmail poller", "household", id, "created", res.Created, "scanned", res.Scanned)
				}
				cancel()
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
	token, err := a.Google.AccessToken(ctx, m.HouseholdID, g.RefreshToken)
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
