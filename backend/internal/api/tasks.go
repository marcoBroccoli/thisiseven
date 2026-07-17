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

var validSections = map[string]bool{"chore": true, "admin": true}
var validRecurrence = map[string]bool{"none": true, "daily": true, "every_2_days": true, "weekly": true}

// scanTask expects: id, title, section, owner, weight, recurrence, due_on,
// origin_label, done_by (nullable member id from open-week completion).
func scanTask(row pgx.Row) (TaskJSON, error) {
	var t TaskJSON
	var dueOn *time.Time
	var origin, doneBy *string
	err := row.Scan(&t.ID, &t.Title, &t.Section, &t.OwnerMemberID, &t.Weight,
		&t.Recurrence, &dueOn, &origin, &doneBy)
	if err != nil {
		return t, err
	}
	if dueOn != nil {
		t.DueOn = strPtr(dateStr(*dueOn))
	}
	t.Done = doneBy != nil
	t.DoneByMemberID = doneBy
	t.MetaLine = metaLine(origin, dueOn, t.Recurrence)
	return t, nil
}

const taskCols = `t.id, t.title, t.section, t.owner_member_id, t.weight,
	t.recurrence, t.due_on, t.origin_label, c.member_id`

func (a *API) fetchTask(ctx context.Context, m *Membership, taskID string) (TaskJSON, error) {
	return scanTask(a.DB.QueryRow(ctx, `
		select `+taskCols+` from tasks t
		left join completions c on c.task_id = t.id and c.week_id = $1
		where t.id = $2 and t.household_id = $3 and t.archived_at is null`,
		m.WeekID, taskID, m.HouseholdID))
}

type taskInput struct {
	Title         *string `json:"title"`
	Section       *string `json:"section"`
	OwnerMemberID *string `json:"owner_member_id"`
	Weight        *int    `json:"weight"`
	Recurrence    *string `json:"recurrence"`
	DueOn         *string `json:"due_on"`
}

func (in *taskInput) validate(w http.ResponseWriter, m *Membership, forCreate bool) (dueOn *time.Time, ok bool) {
	if forCreate {
		if in.Title == nil || strings.TrimSpace(*in.Title) == "" ||
			in.Section == nil || in.OwnerMemberID == nil || in.Weight == nil {
			httpx.Error(w, http.StatusBadRequest, "missing_fields",
				"title, section, owner_member_id and weight are required")
			return nil, false
		}
	}
	if in.Title != nil && strings.TrimSpace(*in.Title) == "" {
		httpx.Error(w, http.StatusBadRequest, "bad_title", "title cannot be empty")
		return nil, false
	}
	if in.Section != nil && !validSections[*in.Section] {
		httpx.Error(w, http.StatusBadRequest, "bad_section", "section must be chore or admin")
		return nil, false
	}
	if in.Weight != nil && (*in.Weight < 1 || *in.Weight > 3) {
		httpx.Error(w, http.StatusBadRequest, "bad_weight", "weight must be 1, 2 or 3")
		return nil, false
	}
	if in.Recurrence != nil && !validRecurrence[*in.Recurrence] {
		httpx.Error(w, http.StatusBadRequest, "bad_recurrence", "unknown recurrence")
		return nil, false
	}
	if in.OwnerMemberID != nil && *in.OwnerMemberID != m.MemberID && *in.OwnerMemberID != m.PartnerID {
		httpx.Error(w, http.StatusNotFound, "not_found", "owner is not in this household")
		return nil, false
	}
	if in.DueOn != nil && *in.DueOn != "" {
		d, err := time.Parse("2006-01-02", *in.DueOn)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_date", "due_on must be YYYY-MM-DD")
			return nil, false
		}
		dueOn = &d
	}
	return dueOn, true
}

// POST /v1/tasks
func (a *API) CreateTask(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	var in taskInput
	if !httpx.Decode(w, r, &in) {
		return
	}
	dueOn, ok := in.validate(w, m, true)
	if !ok {
		return
	}
	recurrence := "none"
	if in.Recurrence != nil {
		recurrence = *in.Recurrence
	}
	var id string
	err := a.DB.QueryRow(r.Context(), `
		insert into tasks (household_id, title, section, owner_member_id, weight,
			recurrence, due_on, created_by)
		values ($1, $2, $3, $4, $5, $6, $7, $8) returning id`,
		m.HouseholdID, strings.TrimSpace(*in.Title), *in.Section, *in.OwnerMemberID,
		*in.Weight, recurrence, dueOn, m.MemberID).Scan(&id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not create task")
		return
	}
	t, err := a.fetchTask(r.Context(), m, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusCreated, t)
}

// PATCH /v1/tasks/{id}
func (a *API) UpdateTask(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	id := chi.URLParam(r, "id")
	var in taskInput
	if !httpx.Decode(w, r, &in) {
		return
	}
	dueOn, ok := in.validate(w, m, false)
	if !ok {
		return
	}
	tag, err := a.DB.Exec(r.Context(), `
		update tasks set
			title = coalesce($1, title),
			section = coalesce($2, section),
			owner_member_id = coalesce($3, owner_member_id),
			weight = coalesce($4, weight),
			recurrence = coalesce($5, recurrence),
			due_on = case when $6::date is not null then $6 else due_on end
		where id = $7 and household_id = $8 and archived_at is null`,
		in.Title, in.Section, in.OwnerMemberID, in.Weight, in.Recurrence, dueOn,
		id, m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not update task")
		return
	}
	if tag.RowsAffected() == 0 {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such task")
		return
	}
	t, err := a.fetchTask(r.Context(), m, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, t)
}

// DELETE /v1/tasks/{id} — archives; completions keep their history.
func (a *API) DeleteTask(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	tag, err := a.DB.Exec(r.Context(), `
		update tasks set archived_at = now()
		where id = $1 and household_id = $2 and archived_at is null`,
		chi.URLParam(r, "id"), m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not delete task")
		return
	}
	if tag.RowsAffected() == 0 {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such task")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// POST /v1/tasks/{id}/toggle — check on/off in the open week. The completion
// belongs to whoever toggled it on (the design credits the pan of the task's
// owner via owner color, but weight lands with the toggler's pan — matching
// the design where checking your task drops your pebble).
func (a *API) ToggleTask(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	id := chi.URLParam(r, "id")
	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		if err := lockHousehold(r.Context(), tx, m.HouseholdID); err != nil {
			return err
		}
		var weight int
		var owner string
		err := tx.QueryRow(r.Context(), `
			select weight, owner_member_id from tasks
			where id = $1 and household_id = $2 and archived_at is null`,
			id, m.HouseholdID).Scan(&weight, &owner)
		if err != nil {
			return err
		}
		tag, err := tx.Exec(r.Context(),
			`delete from completions where task_id = $1 and week_id = $2`, id, m.WeekID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() > 0 {
			return nil // was done — now unchecked
		}
		// Pebble lands in the owner's pan: fairness credits the responsible
		// partner even when the other taps the checkbox.
		_, err = tx.Exec(r.Context(), `
			insert into completions (task_id, week_id, member_id, weight)
			values ($1, $2, $3, $4)`, id, m.WeekID, owner, weight)
		return err
	})
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such task")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not toggle task")
		return
	}
	t, err := a.fetchTask(r.Context(), m, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, t)
}
