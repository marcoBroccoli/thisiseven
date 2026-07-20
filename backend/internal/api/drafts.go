package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

var validReminders = map[string]bool{"on_day": true, "1_day": true, "3_days": true, "1_week": true}

func scanDraft(row pgx.Row) (DraftJSON, error) {
	var d DraftJSON
	var dueOn *time.Time
	var gmailID *string
	var category *string
	var suggestedReply, replyText *string
	var replyStatus string
	err := row.Scan(&d.ID, &d.FromLabel, &d.Subject, &d.Summary, &d.Urgency,
		&d.Title, &d.OwnerMemberID, &d.AmountCents, &dueOn, &d.Reminder,
		&d.Status, &d.CreatedByMemberID, &gmailID, &d.SourceFrom, &d.SourcePreview,
		&category, &d.NeedsReply, &suggestedReply, &replyText, &replyStatus)
	if err != nil {
		return d, err
	}
	d.Category = "other"
	if category != nil && *category != "" {
		d.Category = *category
	}
	d.Gmail = gmailID != nil
	d.GmailMessageID = gmailID
	d.SuggestedReply = suggestedReply
	d.ReplyText = replyText
	d.ReplyStatus = replyStatus
	if d.ReplyStatus == "" {
		d.ReplyStatus = "none"
	}
	if dueOn != nil {
		d.DueOn = strPtr(dateStr(*dueOn))
	}
	return d, nil
}

const draftCols = `id, from_label, subject, summary, urgency, title,
	owner_member_id, amount_cents, due_on, reminder, status, created_by,
	gmail_message_id, source_from, source_preview, category, needs_reply,
	suggested_reply, reply_text, reply_status`

func (a *API) fetchDraft(ctx context.Context, m *Membership, id string) (DraftJSON, error) {
	return scanDraft(a.DB.QueryRow(ctx, `
		select `+draftCols+` from drafts
		where id = $1 and household_id = $2`, id, m.HouseholdID))
}

// GET /v1/drafts?status=pending
func (a *API) ListDrafts(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	status := r.URL.Query().Get("status")
	if status == "" {
		status = "pending"
	}
	if status != "pending" && status != "approved" && status != "dismissed" {
		httpx.Error(w, http.StatusBadRequest, "bad_status", "unknown status filter")
		return
	}
	rows, err := a.DB.Query(r.Context(), `
		select `+draftCols+` from drafts
		where household_id = $1 and status = $2
		order by urgency desc, created_at desc`, m.HouseholdID, status)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "list failed")
		return
	}
	defer rows.Close()
	out := []DraftJSON{}
	for rows.Next() {
		d, err := scanDraft(rows)
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal", "list failed")
			return
		}
		out = append(out, d)
	}
	if rows.Err() != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "list failed")
		return
	}
	httpx.JSON(w, http.StatusOK, out)
}

type draftInput struct {
	FromLabel     *string `json:"from_label"`
	Subject       *string `json:"subject"`
	Summary       *string `json:"summary"`
	Urgency       *int    `json:"urgency"`
	Title         *string `json:"title"`
	OwnerMemberID *string `json:"owner_member_id"`
	AmountCents   *int64  `json:"amount_cents"`
	DueOn         *string `json:"due_on"`
	Reminder      *string `json:"reminder"`
	ReplyText     *string `json:"reply_text"`
	ReplyStatus   *string `json:"reply_status"`
}

var validReplyStatuses = map[string]bool{
	"none": true, "drafted": true, "opened_in_gmail": true,
	"sent_manually": true, "done": true,
}

func validateReplyInput(w http.ResponseWriter, in draftInput) bool {
	if in.ReplyStatus != nil && !validReplyStatuses[*in.ReplyStatus] {
		httpx.Error(w, http.StatusBadRequest, "bad_reply_status", "unknown reply status")
		return false
	}
	if in.ReplyText != nil && len([]rune(*in.ReplyText)) > 4000 {
		httpx.Error(w, http.StatusBadRequest, "reply_too_long", "reply text must be at most 4000 characters")
		return false
	}
	return true
}

func (in *draftInput) parseDue(w http.ResponseWriter) (*time.Time, bool) {
	if in.DueOn == nil || *in.DueOn == "" {
		return nil, true
	}
	d, err := time.Parse("2006-01-02", *in.DueOn)
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "bad_date", "due_on must be YYYY-MM-DD")
		return nil, false
	}
	return &d, true
}

// POST /v1/drafts — a partner proposes something for review.
func (a *API) CreateDraft(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	var in draftInput
	if !httpx.Decode(w, r, &in) {
		return
	}
	if in.FromLabel == nil || strings.TrimSpace(*in.FromLabel) == "" ||
		in.Subject == nil || strings.TrimSpace(*in.Subject) == "" || in.Urgency == nil {
		httpx.Error(w, http.StatusBadRequest, "missing_fields",
			"from_label, subject and urgency are required")
		return
	}
	if *in.Urgency < 1 || *in.Urgency > 3 {
		httpx.Error(w, http.StatusBadRequest, "bad_urgency", "urgency must be 1, 2 or 3")
		return
	}
	title := strings.TrimSpace(*in.Subject)
	if in.Title != nil && strings.TrimSpace(*in.Title) != "" {
		title = strings.TrimSpace(*in.Title)
	}
	owner := m.MemberID
	if in.OwnerMemberID != nil {
		if !strings.EqualFold(*in.OwnerMemberID, m.MemberID) && !strings.EqualFold(*in.OwnerMemberID, m.PartnerID) {
			httpx.Error(w, http.StatusNotFound, "not_found", "owner is not in this household")
			return
		}
		owner = *in.OwnerMemberID
	}
	reminder := "3_days"
	if in.Reminder != nil {
		if !validReminders[*in.Reminder] {
			httpx.Error(w, http.StatusBadRequest, "bad_reminder", "unknown reminder")
			return
		}
		reminder = *in.Reminder
	}
	if in.AmountCents != nil && *in.AmountCents <= 0 {
		httpx.Error(w, http.StatusBadRequest, "bad_amount", "amount_cents must be positive")
		return
	}
	if !validateReplyInput(w, in) {
		return
	}
	dueOn, ok := in.parseDue(w)
	if !ok {
		return
	}
	category := "other"
	if in.AmountCents != nil {
		category = "bills"
	} else if dueOn != nil {
		category = "appointments"
	}
	var replyText *string
	if in.ReplyText != nil {
		if text := strings.TrimSpace(*in.ReplyText); text != "" {
			replyText = &text
		}
	}
	replyStatus := "none"
	if in.ReplyStatus != nil {
		replyStatus = *in.ReplyStatus
	} else if replyText != nil {
		replyStatus = "drafted"
	}
	var id string
	err := a.DB.QueryRow(r.Context(), `
		insert into drafts (household_id, from_label, subject, summary, urgency,
			title, owner_member_id, amount_cents, due_on, reminder, created_by, category,
			reply_text, reply_status)
		values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) returning id`,
		m.HouseholdID, strings.TrimSpace(*in.FromLabel), strings.TrimSpace(*in.Subject),
		in.Summary, *in.Urgency, title, owner, in.AmountCents, dueOn, reminder,
		m.MemberID, category, replyText, replyStatus).Scan(&id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not create draft")
		return
	}
	d, err := a.fetchDraft(r.Context(), m, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusCreated, d)
}

// PATCH /v1/drafts/{id} — everything on the review sheet is editable.
func (a *API) UpdateDraft(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	id := chi.URLParam(r, "id")
	var in draftInput
	if !httpx.Decode(w, r, &in) {
		return
	}
	if in.Title != nil && strings.TrimSpace(*in.Title) == "" {
		httpx.Error(w, http.StatusBadRequest, "bad_title", "title cannot be empty")
		return
	}
	if in.OwnerMemberID != nil && !strings.EqualFold(*in.OwnerMemberID, m.MemberID) && !strings.EqualFold(*in.OwnerMemberID, m.PartnerID) {
		httpx.Error(w, http.StatusNotFound, "not_found", "owner is not in this household")
		return
	}
	if in.Reminder != nil && !validReminders[*in.Reminder] {
		httpx.Error(w, http.StatusBadRequest, "bad_reminder", "unknown reminder")
		return
	}
	if in.AmountCents != nil && *in.AmountCents <= 0 {
		httpx.Error(w, http.StatusBadRequest, "bad_amount", "amount_cents must be positive")
		return
	}
	if !validateReplyInput(w, in) {
		return
	}
	dueOn, ok := in.parseDue(w)
	if !ok {
		return
	}
	tag, err := a.DB.Exec(r.Context(), `
		update drafts set
			title = coalesce($1, title),
			owner_member_id = coalesce($2, owner_member_id),
			amount_cents = coalesce($3, amount_cents),
			due_on = case when $4::date is not null then $4 else due_on end,
			reminder = coalesce($5, reminder),
			reply_text = case when $6::text is not null then nullif(trim($6), '') else reply_text end,
			reply_status = coalesce($7, reply_status)
		where id = $8 and household_id = $9 and status = 'pending'`,
		in.Title, in.OwnerMemberID, in.AmountCents, dueOn, in.Reminder,
		in.ReplyText, in.ReplyStatus, id, m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not update draft")
		return
	}
	if tag.RowsAffected() == 0 {
		httpx.Error(w, http.StatusNotFound, "not_found", "no pending draft with that id")
		return
	}
	d, err := a.fetchDraft(r.Context(), m, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, d)
}

// POST /v1/drafts/{id}/approve — one transaction: draft → approved, admin task born.
func (a *API) ApproveDraft(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	id := chi.URLParam(r, "id")
	var taskID string
	var evTitle, evFrom, evReminder string
	var evAmount *int64
	var evDue *time.Time
	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		var title, owner, fromLabel string
		var dueOn *time.Time
		err := tx.QueryRow(r.Context(), `
			select title, owner_member_id, from_label, due_on, amount_cents, reminder
			from drafts
			where id = $1 and household_id = $2 and status = 'pending' for update`,
			id, m.HouseholdID).Scan(&title, &owner, &fromLabel, &dueOn, &evAmount, &evReminder)
		if err != nil {
			return err
		}
		evTitle, evFrom, evDue = title, fromLabel, dueOn
		if err := tx.QueryRow(r.Context(), `
			insert into tasks (household_id, title, section, owner_member_id, weight,
				recurrence, due_on, origin_label, created_by)
			values ($1, $2, 'admin', $3, 2, 'none', $4, $5, $6) returning id`,
			m.HouseholdID, title, owner, dueOn, "APPROVED · "+strings.ToUpper(fromLabel),
			m.MemberID).Scan(&taskID); err != nil {
			return err
		}
		_, err = tx.Exec(r.Context(), `
			update drafts set status = 'approved', resulting_task_id = $1, resolved_at = now()
			where id = $2`, taskID, id)
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "no pending draft with that id")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not approve draft")
		return
	}
	// Calendar write happens after commit — a Google failure never undoes an
	// approval; the response carries calendar_error instead.
	calendarErr := a.publishTaskToCalendar(r.Context(), m, taskID,
		evTitle, evFrom, evAmount, evDue, evReminder)
	d, err1 := a.fetchDraft(r.Context(), m, id)
	t, err2 := a.fetchTask(r.Context(), m, taskID)
	if err1 != nil || err2 != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	out := map[string]any{"draft": d, "task": t}
	if calendarErr != "" {
		out["calendar_error"] = calendarErr
	}
	httpx.JSON(w, http.StatusOK, out)
}

// POST /v1/drafts/{id}/dismiss
func (a *API) DismissDraft(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	id := chi.URLParam(r, "id")
	tag, err := a.DB.Exec(r.Context(), `
		update drafts set status = 'dismissed', resolved_at = now()
		where id = $1 and household_id = $2 and status = 'pending'`, id, m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not dismiss draft")
		return
	}
	if tag.RowsAffected() == 0 {
		httpx.Error(w, http.StatusNotFound, "not_found", "no pending draft with that id")
		return
	}
	d, err := a.fetchDraft(r.Context(), m, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, d)
}
