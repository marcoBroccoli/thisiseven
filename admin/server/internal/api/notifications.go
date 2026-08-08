package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// Composing a push writes a row and stops. There is no APNs sender yet (that is
// the notifications slice of the product roadmap), so the console's job is to
// make the queue real, honest and reversible: every row is cancellable while it
// is still 'queued', and the UI states plainly that nothing is delivered today.
const outboxDisclaimer = "Queued only. Even has no APNs sender yet — these rows wait in admin.notification_outbox until the delivery job ships. Nothing reaches a phone."

const (
	maxTitleLen = 80
	maxBodyLen  = 400
)

type outboxRow struct {
	ID             string  `json:"id"`
	Audience       string  `json:"audience"`
	HouseholdID    *string `json:"household_id"`
	HouseholdName  *string `json:"household_name"`
	UserID         *string `json:"user_id"`
	UserEmail      *string `json:"user_email"`
	Title          string  `json:"title"`
	Body           string  `json:"body"`
	ScheduledAt    string  `json:"scheduled_at"`
	Status         string  `json:"status"`
	RecipientCount int     `json:"recipient_count"`
	DeliveredCount int     `json:"delivered_count"`
	Error          *string `json:"error"`
	CreatedBy      string  `json:"created_by"`
	CreatedAt      string  `json:"created_at"`
	SentAt         *string `json:"sent_at"`
}

func (a *API) ListNotifications(w http.ResponseWriter, r *http.Request) {
	p := readPage(r)
	pattern := p.like()
	status := r.URL.Query().Get("status")

	// The joins live in the shared FROM so the count and the page cannot drift
	// apart. Both are LEFT joins: a household deleted after a push was queued
	// must not make the row vanish from the outbox — that history is the point.
	const from = `
		from admin.notification_outbox o
		left join households h on h.id = o.household_id
		left join auth.users u on u.id = o.user_id
		 where ($1 = '%' or o.title ilike $1 or o.body ilike $1 or o.created_by ilike $1)
		   and ($2 = '' or o.status = $2)`

	var total int
	if err := a.DB.QueryRow(r.Context(), `select count(*) `+from, pattern, status).Scan(&total); err != nil {
		fail(w, "count outbox", err)
		return
	}
	rows, err := a.DB.Query(r.Context(), `
		select o.id::text, o.audience, o.household_id::text, h.name,
		       o.user_id::text, u.email, o.title, o.body, o.scheduled_at, o.status,
		       o.recipient_count, o.delivered_count, o.error, o.created_by,
		       o.created_at, o.sent_at
		  `+from+`
		 order by o.created_at desc
		 limit $3 offset $4`, pattern, status, p.Limit, p.Offset)
	if err != nil {
		fail(w, "list outbox", err)
		return
	}
	defer rows.Close()
	out := []outboxRow{}
	for rows.Next() {
		var o outboxRow
		var scheduled, created time.Time
		var sent *time.Time
		if err := rows.Scan(&o.ID, &o.Audience, &o.HouseholdID, &o.HouseholdName,
			&o.UserID, &o.UserEmail, &o.Title, &o.Body, &scheduled, &o.Status,
			&o.RecipientCount, &o.DeliveredCount, &o.Error, &o.CreatedBy,
			&created, &sent); err != nil {
			fail(w, "scan outbox", err)
			return
		}
		o.ScheduledAt = scheduled.UTC().Format(time.RFC3339)
		o.CreatedAt = created.UTC().Format(time.RFC3339)
		o.SentAt = tsPtr(sent)
		out = append(out, o)
	}
	if err := rows.Err(); err != nil {
		fail(w, "iterate outbox", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"rows": out, "page": p.meta(total), "notice": outboxDisclaimer,
	})
}

type notificationRequest struct {
	Audience    string  `json:"audience"`
	HouseholdID *string `json:"household_id"`
	UserID      *string `json:"user_id"`
	Title       string  `json:"title"`
	Body        string  `json:"body"`
	// ScheduledAt is RFC3339; empty means now.
	ScheduledAt string `json:"scheduled_at"`
}

// CreateNotification validates the target against real rows before queueing, so
// a typo'd household id fails at compose time rather than in a delivery job
// nobody is watching. The recipient count is an estimate stamped now — it is
// what the operator was shown when they pressed send.
func (a *API) CreateNotification(w http.ResponseWriter, r *http.Request) {
	adm, _ := adminFrom(r.Context())
	var req notificationRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	req.Body = strings.TrimSpace(req.Body)
	if req.Title == "" || len([]rune(req.Title)) > maxTitleLen {
		writeErr(w, http.StatusBadRequest, "bad_title",
			"Title is required and at most 80 characters.")
		return
	}
	if req.Body == "" || len([]rune(req.Body)) > maxBodyLen {
		writeErr(w, http.StatusBadRequest, "bad_body",
			"Body is required and at most 400 characters.")
		return
	}

	scheduled := a.now()
	if req.ScheduledAt != "" {
		t, err := time.Parse(time.RFC3339, req.ScheduledAt)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "bad_schedule",
				"scheduled_at must be an RFC3339 timestamp.")
			return
		}
		scheduled = t
	}

	var householdID, userID *string
	var recipients int
	switch req.Audience {
	case "all":
		if err := a.DB.QueryRow(r.Context(),
			`select count(distinct user_id) from members where left_at is null`).Scan(&recipients); err != nil {
			fail(w, "count recipients", err)
			return
		}
	case "household":
		if req.HouseholdID == nil || *req.HouseholdID == "" {
			writeErr(w, http.StatusBadRequest, "missing_target", "Pick a household.")
			return
		}
		err := a.DB.QueryRow(r.Context(), `
			select count(*) from members
			 where household_id::text = $1 and left_at is null`, *req.HouseholdID).Scan(&recipients)
		if err != nil {
			fail(w, "count household recipients", err)
			return
		}
		var exists bool
		if err := a.DB.QueryRow(r.Context(),
			`select exists(select 1 from households where id::text = $1)`,
			*req.HouseholdID).Scan(&exists); err != nil {
			fail(w, "check household", err)
			return
		}
		if !exists {
			writeErr(w, http.StatusNotFound, "not_found", "No household with that id.")
			return
		}
		householdID = req.HouseholdID
	case "user":
		if req.UserID == nil || *req.UserID == "" {
			writeErr(w, http.StatusBadRequest, "missing_target", "Pick a user.")
			return
		}
		var exists bool
		if err := a.DB.QueryRow(r.Context(),
			`select exists(select 1 from auth.users where id::text = $1)`,
			*req.UserID).Scan(&exists); err != nil {
			fail(w, "check user", err)
			return
		}
		if !exists {
			writeErr(w, http.StatusNotFound, "not_found", "No user with that id.")
			return
		}
		userID, recipients = req.UserID, 1
	default:
		writeErr(w, http.StatusBadRequest, "bad_audience",
			`audience must be "all", "household" or "user".`)
		return
	}

	var id string
	if err := a.DB.QueryRow(r.Context(), `
		insert into admin.notification_outbox
		  (audience, household_id, user_id, title, body, scheduled_at, recipient_count, created_by)
		values ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, $8)
		returning id::text`,
		req.Audience, householdID, userID, req.Title, req.Body,
		scheduled, recipients, adm.Email).Scan(&id); err != nil {
		fail(w, "queue notification", err)
		return
	}
	a.audit(r, auditEntry{
		Action: "notification.queue", TargetType: "notification", TargetID: id,
		Summary: "Queued “" + req.Title + "” to " + req.Audience,
		After: map[string]any{
			"audience": req.Audience, "household_id": householdID, "user_id": userID,
			"title": req.Title, "body": req.Body,
			"scheduled_at": scheduled.UTC().Format(time.RFC3339),
			"recipient_count": recipients,
		},
	})
	writeJSON(w, http.StatusCreated, map[string]any{
		"ok": true, "id": id, "recipient_count": recipients, "notice": outboxDisclaimer,
	})
}

// CancelNotification retracts a queued row. Anything already claimed by a
// sender is left alone — the console must not race a delivery job it cannot
// see, so the update is conditional on the status still being 'queued'.
func (a *API) CancelNotification(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var status, title string
	err := a.DB.QueryRow(r.Context(),
		`select status, title from admin.notification_outbox where id::text = $1`, id).
		Scan(&status, &title)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "not_found", "No queued notification with that id.")
		return
	}
	if err != nil {
		fail(w, "load notification", err)
		return
	}
	if status != "queued" {
		writeErr(w, http.StatusConflict, "not_queued",
			"That notification is already "+status+" and can no longer be cancelled.")
		return
	}
	tag, err := a.DB.Exec(r.Context(), `
		update admin.notification_outbox set status = 'cancelled'
		 where id::text = $1 and status = 'queued'`, id)
	if err != nil {
		fail(w, "cancel notification", err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusConflict, "not_queued", "That notification was picked up before it could be cancelled.")
		return
	}
	a.audit(r, auditEntry{
		Action: "notification.cancel", TargetType: "notification", TargetID: id,
		Summary: "Cancelled “" + title + "”",
		Before:  map[string]any{"status": status}, After: map[string]any{"status": "cancelled"},
	})
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

type pickerOption struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Sub   string `json:"sub"`
}

// NotificationTargets feeds the compose form's two pickers with a searchable
// slice of real rows — the form must never accept a hand-typed uuid.
func (a *API) NotificationTargets(w http.ResponseWriter, r *http.Request) {
	p := readPage(r)
	pattern := p.like()

	households := []pickerOption{}
	rows, err := a.DB.Query(r.Context(), `
		select h.id::text, h.name,
		       (select count(*) from members m where m.household_id = h.id and m.left_at is null)
		  from households h
		 where $1 = '%' or h.name ilike $1 or h.id::text ilike $1
		 order by h.name limit 25`, pattern)
	if err != nil {
		fail(w, "target households", err)
		return
	}
	for rows.Next() {
		var o pickerOption
		var n int
		if err := rows.Scan(&o.ID, &o.Label, &n); err != nil {
			rows.Close()
			fail(w, "scan target household", err)
			return
		}
		o.Sub = plural(n, "active member", "active members")
		households = append(households, o)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fail(w, "iterate target households", err)
		return
	}

	users := []pickerOption{}
	rows, err = a.DB.Query(r.Context(), `
		select u.id::text, coalesce(u.email, u.id::text),
		       coalesce((select m.display_name from members m
		                  where m.user_id = u.id order by m.created_at limit 1), '—')
		  from auth.users u
		 where $1 = '%' or coalesce(u.email,'') ilike $1 or u.id::text ilike $1
		 order by u.created_at desc limit 25`, pattern)
	if err != nil {
		fail(w, "target users", err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		var o pickerOption
		if err := rows.Scan(&o.ID, &o.Label, &o.Sub); err != nil {
			fail(w, "scan target user", err)
			return
		}
		users = append(users, o)
	}
	if err := rows.Err(); err != nil {
		fail(w, "iterate target users", err)
		return
	}

	var all int
	if err := a.DB.QueryRow(r.Context(),
		`select count(distinct user_id) from members where left_at is null`).Scan(&all); err != nil {
		fail(w, "count all", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"households": households, "users": users, "all_recipients": all,
	})
}

func plural(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return itoa(n) + " " + many
}
