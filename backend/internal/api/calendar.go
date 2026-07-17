package api

import (
	"net/http"
	"sort"
	"time"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// CalendarItemJSON is one dated item on the household's shared calendar view:
// a pending draft with a due date, or a task with a due date.
type CalendarItemJSON struct {
	Kind           string  `json:"kind"` // "draft" | "task"
	ID             string  `json:"id"`
	Title          string  `json:"title"`
	Category       string  `json:"category,omitempty"`
	OwnerMemberID  string  `json:"owner_member_id"`
	AmountCents    *int64  `json:"amount_cents,omitempty"`
	DueOn          string  `json:"due_on"`
	Done           *bool   `json:"done,omitempty"`
	GoogleEventURL *string `json:"google_event_url,omitempty"`
}

// Calendar returns the household's dated items in a window.
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

	drows, err := a.DB.Query(ctx, `
		select id, title, coalesce(category, 'other'), owner_member_id, amount_cents, due_on
		from drafts
		where household_id = $1 and status = 'pending'
		  and due_on is not null and due_on between $2 and $3`,
		m.HouseholdID, from, to)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "calendar failed")
		return
	}
	defer drows.Close()
	for drows.Next() {
		var it CalendarItemJSON
		var due time.Time
		if err := drows.Scan(&it.ID, &it.Title, &it.Category, &it.OwnerMemberID,
			&it.AmountCents, &due); err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal", "calendar failed")
			return
		}
		it.Kind = "draft"
		it.DueOn = dateStr(due)
		items = append(items, it)
	}
	drows.Close()

	trows, err := a.DB.Query(ctx, `
		select `+taskCols+` from tasks t
		left join completions c on c.task_id = t.id and c.week_id = $1
		where t.household_id = $2 and t.archived_at is null
		  and t.due_on is not null and t.due_on between $3 and $4`,
		m.WeekID, m.HouseholdID, from, to)
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
		done := t.Done
		items = append(items, CalendarItemJSON{
			Kind:           "task",
			ID:             t.ID,
			Title:          t.Title,
			OwnerMemberID:  t.OwnerMemberID,
			DueOn:          *t.DueOn,
			Done:           &done,
			GoogleEventURL: t.GoogleEventURL,
		})
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].DueOn != items[j].DueOn {
			return items[i].DueOn < items[j].DueOn
		}
		if items[i].Kind != items[j].Kind {
			return items[i].Kind < items[j].Kind // drafts before tasks
		}
		return items[i].Title < items[j].Title
	})

	httpx.JSON(w, http.StatusOK, map[string]any{
		"from":  dateStr(from),
		"to":    dateStr(to),
		"items": items,
	})
}
