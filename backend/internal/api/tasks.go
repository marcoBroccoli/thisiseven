package api

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

var validSections = map[string]bool{"chore": true, "admin": true}
var validRecurrence = map[string]bool{"none": true, "daily": true, "every_2_days": true, "weekly": true}

func usesOccurrenceCompletions(recurrence string) bool {
	return recurrence == "daily" || recurrence == "every_2_days"
}

func dateOnly(t time.Time) time.Time {
	y, month, day := t.In(Amsterdam).Date()
	return time.Date(y, month, day, 0, 0, 0, 0, time.UTC)
}

func recurrenceAnchor(dueOn *time.Time, createdAt time.Time) time.Time {
	if dueOn != nil {
		return dateOnly(*dueOn)
	}
	return dateOnly(createdAt)
}

// recursOnDate describes the scheduled occurrence day for a task. The due
// date anchors a repeat when one was selected; otherwise the capture date is
// the anchor. This gives a manual "wash the dog" todo a predictable cadence
// without requiring a cost or a separate schedule screen.
func recursOnDate(recurrence string, dueOn *time.Time, createdAt, day time.Time) bool {
	anchor := recurrenceAnchor(dueOn, createdAt)
	day = dateOnly(day)
	if day.Before(anchor) {
		return false
	}
	switch recurrence {
	case "daily":
		return true
	case "every_2_days":
		return int(day.Sub(anchor).Hours()/24)%2 == 0
	default:
		return false
	}
}

// scanTask expects: id, title, section, owner, weight, recurrence, due_on,
// origin_label, Google mapping/sync fields, done_by. Daily and every-two-day
// tasks take done_by from their current occurrence; other tasks use the open
// week completion.
func scanTask(row pgx.Row) (TaskJSON, error) {
	var t TaskJSON
	var dueOn, calendarSyncedAt *time.Time
	var origin, doneBy *string
	err := row.Scan(&t.ID, &t.Title, &t.Section, &t.OwnerMemberID, &t.Weight,
		&t.Recurrence, &dueOn, &origin, &t.GoogleEventURL, &t.CalendarSyncState,
		&calendarSyncedAt, &t.CalendarLastError, &doneBy)
	if err != nil {
		return t, err
	}
	if dueOn != nil {
		t.DueOn = strPtr(dateStr(*dueOn))
	}
	if calendarSyncedAt != nil {
		t.CalendarLastSyncedAt = strPtr(calendarSyncedAt.UTC().Format(time.RFC3339))
	}
	t.Done = doneBy != nil
	t.DoneByMemberID = doneBy
	t.MetaLine = metaLine(origin, dueOn, t.Recurrence)
	return t, nil
}

const taskCols = `t.id, t.title, t.section, t.owner_member_id, t.weight,
	t.recurrence, t.due_on, t.origin_label, t.google_event_url, t.calendar_sync_state,
	t.calendar_last_synced_at, t.calendar_last_error,
	case when t.recurrence in ('daily', 'every_2_days') then rc.member_id else c.member_id end`

const visibleTodayRecurrence = `
	and (
		t.recurrence not in ('daily', 'every_2_days')
		or (t.recurrence = 'daily' and $2::date >= coalesce(t.due_on, t.created_at::date))
		or (t.recurrence = 'every_2_days'
			and $2::date >= coalesce(t.due_on, t.created_at::date)
			and mod($2::date - coalesce(t.due_on, t.created_at::date), 2) = 0)
	)`

func (a *API) fetchTask(ctx context.Context, m *Membership, taskID string) (TaskJSON, error) {
	return scanTask(a.DB.QueryRow(ctx, `
		select `+taskCols+` from tasks t
		left join completions c on c.task_id = t.id and c.week_id = $1
		left join recurring_completions rc on rc.task_id = t.id and rc.occurrence_on = $2
		where t.id = $3 and t.household_id = $4 and t.archived_at is null`,
		m.WeekID, today(), taskID, m.HouseholdID))
}

type taskInput struct {
	Title         *string `json:"title"`
	Section       *string `json:"section"`
	OwnerMemberID *string `json:"owner_member_id"`
	Weight        *int    `json:"weight"`
	Recurrence    *string `json:"recurrence"`
	DueOn         *string `json:"due_on"`
	ClearDueOn    bool    `json:"clear_due_on"`
}

type calendarResolutionInput struct {
	Action string `json:"action"`
}

const (
	calendarResolutionAcknowledge = "acknowledge"
	calendarResolutionRestore     = "restore"
	calendarResolutionRetry       = "retry"
)

type calendarResolutionTask struct {
	ID        string
	Title     string
	DueOn     *time.Time
	EventID   *string
	SyncState string
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
	if in.OwnerMemberID != nil && !strings.EqualFold(*in.OwnerMemberID, m.MemberID) && !strings.EqualFold(*in.OwnerMemberID, m.PartnerID) {
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
	if in.ClearDueOn && in.DueOn != nil && *in.DueOn != "" {
		httpx.Error(w, http.StatusBadRequest, "bad_date", "set due_on or clear_due_on, not both")
		return nil, false
	}
	return dueOn, true
}

func (a *API) calendarTaskForResolution(ctx context.Context, m *Membership, taskID string) (calendarResolutionTask, error) {
	var task calendarResolutionTask
	err := a.DB.QueryRow(ctx, `
		select id, title, due_on, google_event_id, calendar_sync_state
		from tasks where id = $1 and household_id = $2 and archived_at is null`,
		taskID, m.HouseholdID).
		Scan(&task.ID, &task.Title, &task.DueOn, &task.EventID, &task.SyncState)
	return task, err
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
	// A dated manual todo follows the same Calendar path as an approved
	// Gmail suggestion. A Calendar failure must not prevent the household
	// from capturing the todo locally.
	if calendarErr := a.publishTaskToCalendar(r.Context(), m, id,
		strings.TrimSpace(*in.Title), "", nil, dueOn, "1_day"); calendarErr != "" {
		slog.Warn("manual todo calendar publish failed", "task", id, "err", calendarErr)
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
	var previousEventID *string
	if err := a.DB.QueryRow(r.Context(), `
		select google_event_id from tasks where id = $1 and household_id = $2 and archived_at is null`,
		id, m.HouseholdID).Scan(&previousEventID); errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such task")
		return
	} else if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not load task")
		return
	}
	tag, err := a.DB.Exec(r.Context(), `
		update tasks set
			title = coalesce($1, title),
			section = coalesce($2, section),
			owner_member_id = coalesce($3, owner_member_id),
			weight = coalesce($4, weight),
			recurrence = coalesce($5, recurrence),
			due_on = case
				when $6 then null
				when $7::date is not null then $7
				else due_on
			end
		where id = $8 and household_id = $9 and archived_at is null`,
		in.Title, in.Section, in.OwnerMemberID, in.Weight, in.Recurrence, in.ClearDueOn, dueOn,
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
	if t.DueOn != nil {
		due, parseErr := time.Parse("2006-01-02", *t.DueOn)
		if parseErr == nil {
			if calendarErr := a.publishTaskToCalendar(r.Context(), m, t.ID, t.Title, "", nil, &due, "1_day"); calendarErr != "" {
				slog.Warn("todo calendar update failed", "task", t.ID, "err", calendarErr)
			}
			t, _ = a.fetchTask(r.Context(), m, id)
		}
	} else if in.ClearDueOn {
		if calendarErr := a.removeTaskFromCalendar(r.Context(), m, t.ID, previousEventID); calendarErr != "" {
			slog.Warn("todo calendar removal failed", "task", t.ID, "err", calendarErr)
		}
		if refreshed, fetchErr := a.fetchTask(r.Context(), m, id); fetchErr == nil {
			t = refreshed
		}
	}
	httpx.JSON(w, http.StatusOK, t)
}

// POST /v1/tasks/{id}/calendar/resolve {action:"acknowledge"|"restore"|"retry"}
//
// A Calendar edit is already copied into the local todo during reconciliation,
// so acknowledge only clears its review marker. A remote deletion is never
// silently accepted: restore creates a new event from the surviving local todo.
func (a *API) ResolveTaskCalendar(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	id := chi.URLParam(r, "id")
	var in calendarResolutionInput
	if !httpx.Decode(w, r, &in) {
		return
	}
	in.Action = strings.TrimSpace(in.Action)
	if in.Action != calendarResolutionAcknowledge && in.Action != calendarResolutionRestore && in.Action != calendarResolutionRetry {
		httpx.Error(w, http.StatusBadRequest, "bad_calendar_action", "action must be acknowledge, restore or retry")
		return
	}

	if in.Action != calendarResolutionAcknowledge {
		if !a.googleReady(w) {
			return
		}
		if _, err := a.googleAccount(r.Context(), m.HouseholdID); errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, http.StatusConflict, "not_connected", "connect the household Google account first")
			return
		} else if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal", "could not load the Google connection")
			return
		}
	}

	task, err := a.calendarTaskForResolution(r.Context(), m, id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such task")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not load task")
		return
	}

	switch in.Action {
	case calendarResolutionAcknowledge:
		if task.SyncState != "external_changed" {
			httpx.Error(w, http.StatusConflict, "calendar_not_pending", "this Calendar change is already resolved")
			return
		}
		_, err = a.DB.Exec(r.Context(), `
			update tasks set calendar_sync_state = 'synced', calendar_last_error = null,
				calendar_last_synced_at = now()
			where id = $1 and household_id = $2`, task.ID, m.HouseholdID)

	case calendarResolutionRestore:
		if task.SyncState != "external_deleted" {
			httpx.Error(w, http.StatusConflict, "calendar_not_deleted", "only a todo removed in Calendar can be restored")
			return
		}
		if task.DueOn == nil {
			httpx.Error(w, http.StatusConflict, "calendar_not_scheduled", "add a due date before restoring this todo")
			return
		}
		_, err = a.DB.Exec(r.Context(), `
			update tasks set google_event_id = null, google_event_url = null,
				calendar_sync_state = 'not_scheduled', calendar_last_error = null
			where id = $1 and household_id = $2`, task.ID, m.HouseholdID)
		if err == nil {
			if calendarErr := a.publishTaskToCalendar(r.Context(), m, task.ID, task.Title, "", nil, task.DueOn, "1_day"); calendarErr != "" {
				slog.Warn("todo Calendar restore failed", "task", task.ID, "err", calendarErr)
			}
		}

	case calendarResolutionRetry:
		if task.SyncState != "retry_required" {
			httpx.Error(w, http.StatusConflict, "calendar_not_retryable", "this todo does not need a Calendar retry")
			return
		}
		if task.DueOn == nil {
			if calendarErr := a.removeTaskFromCalendar(r.Context(), m, task.ID, task.EventID); calendarErr != "" {
				slog.Warn("todo Calendar removal retry failed", "task", task.ID, "err", calendarErr)
			}
		} else if calendarErr := a.publishTaskToCalendar(r.Context(), m, task.ID, task.Title, "", nil, task.DueOn, "1_day"); calendarErr != "" {
			slog.Warn("todo Calendar publish retry failed", "task", task.ID, "err", calendarErr)
		}
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not resolve the Calendar todo")
		return
	}

	updated, err := a.fetchTask(r.Context(), m, task.ID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, updated)
}

// DELETE /v1/tasks/{id} — archives; completions keep their history.
func (a *API) DeleteTask(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	id := chi.URLParam(r, "id")
	var eventID *string
	if err := a.DB.QueryRow(r.Context(), `
		select google_event_id from tasks where id = $1 and household_id = $2 and archived_at is null`,
		id, m.HouseholdID).Scan(&eventID); errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such task")
		return
	} else if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not load task")
		return
	}
	tag, err := a.DB.Exec(r.Context(), `
		update tasks set archived_at = now()
		where id = $1 and household_id = $2 and archived_at is null`,
		id, m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not delete task")
		return
	}
	if tag.RowsAffected() > 0 && eventID != nil {
		if err := a.deleteTaskCalendarEvent(r.Context(), m, *eventID); err != nil {
			slog.Warn("calendar delete failed", "task", id, "err", err)
		}
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
		var owner, recurrence string
		var dueOn *time.Time
		var createdAt time.Time
		err := tx.QueryRow(r.Context(), `
			select weight, owner_member_id, recurrence, due_on, created_at from tasks
			where id = $1 and household_id = $2 and archived_at is null`,
			id, m.HouseholdID).Scan(&weight, &owner, &recurrence, &dueOn, &createdAt)
		if err != nil {
			return err
		}
		if usesOccurrenceCompletions(recurrence) {
			occurrence := today()
			if !recursOnDate(recurrence, dueOn, createdAt, occurrence) {
				return errTaskNotDue
			}
			tag, err := tx.Exec(r.Context(), `
				delete from recurring_completions where task_id = $1 and occurrence_on = $2`, id, occurrence)
			if err != nil {
				return err
			}
			if tag.RowsAffected() > 0 {
				return nil
			}
			_, err = tx.Exec(r.Context(), `
				insert into recurring_completions (task_id, occurrence_on, member_id, weight)
				values ($1, $2, $3, $4)`, id, occurrence, owner, weight)
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
	if errors.Is(err, errTaskNotDue) {
		httpx.Error(w, http.StatusConflict, "task_not_due", "this recurring todo is not due today")
		return
	}
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

var errTaskNotDue = errors.New("task is not due")
