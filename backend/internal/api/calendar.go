package api

import (
	"net/http"
	"sort"
	"time"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// CalendarItemJSON is one dated todo on the household's shared calendar view.
type CalendarItemJSON struct {
	Kind           string  `json:"kind"` // "task"
	ID             string  `json:"id"`
	Title          string  `json:"title"`
	Category       string  `json:"category,omitempty"`
	OwnerMemberID  string  `json:"owner_member_id"`
	AmountCents    *int64  `json:"amount_cents,omitempty"`
	DueOn          string  `json:"due_on"`
	Done           *bool   `json:"done,omitempty"`
	GoogleEventURL *string `json:"google_event_url,omitempty"`
}

func calendarOccurrences(recurrence string, dueOn *time.Time, createdAt, from, to time.Time) []time.Time {
	// Calendar ranges are civil days. Normalizing prevents a noon timestamp
	// from skipping an otherwise-in-range all-day occurrence.
	from, to = dateOnly(from), dateOnly(to)
	if recurrence == "none" {
		if dueOn == nil || dueOn.Before(from) || dueOn.After(to) {
			return nil
		}
		return []time.Time{dateOnly(*dueOn)}
	}

	interval := 7
	switch recurrence {
	case "daily":
		interval = 1
	case "every_2_days":
		interval = 2
	case "weekly":
		interval = 7
	default:
		return nil
	}
	anchor := recurrenceAnchor(dueOn, createdAt)
	if anchor.After(to) {
		return nil
	}
	occurrence := anchor
	if occurrence.Before(from) {
		days := int(from.Sub(anchor).Hours() / 24)
		occurrence = anchor.AddDate(0, 0, (days/interval)*interval)
		if occurrence.Before(from) {
			occurrence = occurrence.AddDate(0, 0, interval)
		}
	}
	var dates []time.Time
	for !occurrence.After(to) {
		dates = append(dates, occurrence)
		occurrence = occurrence.AddDate(0, 0, interval)
	}
	return dates
}

// Calendar returns the household's dated todos in a window. Gmail suggestions
// stay in the Todo review queue until someone turns them into a real todo.
// GET /v1/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD — defaults to
// (first of this month − 7d) … (today + 60d); the span is capped at 120d.
func (a *API) Calendar(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	ctx := r.Context()

	now := time.Now().In(Amsterdam)
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, Amsterdam)
	from := monthStart.AddDate(0, 0, -7)
	to := now.AddDate(0, 0, 60)
	if q := r.URL.Query().Get("from"); q != "" {
		d, err := time.ParseInLocation("2006-01-02", q, Amsterdam)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_date", "from must be YYYY-MM-DD")
			return
		}
		from = d
	}
	if q := r.URL.Query().Get("to"); q != "" {
		d, err := time.ParseInLocation("2006-01-02", q, Amsterdam)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_date", "to must be YYYY-MM-DD")
			return
		}
		to = d
	}
	if to.Before(from) {
		httpx.Error(w, http.StatusBadRequest, "bad_range", "to must not be before from")
		return
	}
	if cap := from.AddDate(0, 0, 120); to.After(cap) {
		to = cap
	}

	items := []CalendarItemJSON{}

	trows, err := a.DB.Query(ctx, `
		select `+taskCols+` from tasks t
		left join completions c on c.task_id = t.id and c.week_id = $1
		left join recurring_completions rc on rc.task_id = t.id and rc.occurrence_on = $2
		where t.household_id = $3 and t.archived_at is null
		  and (
			(t.recurrence = 'none' and t.due_on between $4 and $5)
			or (t.recurrence <> 'none' and coalesce(t.due_on, t.created_at::date) <= $5)
		  )
		order by t.created_at`,
		m.WeekID, today(), m.HouseholdID, from, to)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "calendar failed")
		return
	}
	defer trows.Close()
	for trows.Next() {
		t, err := scanTask(trows)
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal", "calendar failed")
			return
		}
		var anchor *time.Time
		if t.DueOn != nil {
			if d, err := time.Parse("2006-01-02", *t.DueOn); err == nil {
				anchor = &d
			}
		}
		for _, occurrence := range calendarOccurrences(t.Recurrence, anchor, today(), from, to) {
			itemID := t.ID
			if t.Recurrence != "none" {
				itemID += ":" + dateStr(occurrence)
			}
			var done *bool
			if t.Recurrence == "none" || dateStr(occurrence) == dateStr(today()) ||
				(t.Recurrence == "weekly" && !occurrence.Before(dateOnly(m.WeekStart)) && occurrence.Before(dateOnly(m.WeekStart).AddDate(0, 0, 7))) {
				isDone := t.Done
				done = &isDone
			}
			items = append(items, CalendarItemJSON{
				Kind:           "task",
				ID:             itemID,
				Title:          t.Title,
				OwnerMemberID:  t.OwnerMemberID,
				DueOn:          dateStr(occurrence),
				Done:           done,
				GoogleEventURL: t.GoogleEventURL,
			})
		}
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].DueOn != items[j].DueOn {
			return items[i].DueOn < items[j].DueOn
		}
		return items[i].Title < items[j].Title
	})

	httpx.JSON(w, http.StatusOK, map[string]any{
		"from":  dateStr(from),
		"to":    dateStr(to),
		"items": items,
	})
}
