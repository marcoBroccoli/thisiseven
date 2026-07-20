package api

import (
	"net/http"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// GET /v1/summary — everything the Today screen needs in one round trip.
func (a *API) Summary(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	ctx := r.Context()

	type pebble struct {
		MemberID string `json:"member_id"`
		Weight   int    `json:"weight"`
	}
	pebbles := []pebble{}
	myWeight, partnerWeight := 0, 0
	rows, err := a.DB.Query(ctx, `
		select member_id, weight from (
			select c.member_id, c.weight, c.completed_at
			from completions c where c.week_id = $1
			union all
			select rc.member_id, rc.weight, rc.completed_at
			from recurring_completions rc
			join tasks t on t.id = rc.task_id
			where t.household_id = $2 and rc.occurrence_on >= $3 and rc.occurrence_on <= $4
		) completions_this_week
		order by completed_at`, m.WeekID, m.HouseholdID, m.WeekStart, today())
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "summary failed")
		return
	}
	for rows.Next() {
		var p pebble
		if err := rows.Scan(&p.MemberID, &p.Weight); err != nil {
			rows.Close()
			httpx.Error(w, http.StatusInternalServerError, "internal", "summary failed")
			return
		}
		pebbles = append(pebbles, p)
		if p.MemberID == m.MemberID {
			myWeight += p.Weight
		} else {
			partnerWeight += p.Weight
		}
	}
	rows.Close()
	if rows.Err() != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "summary failed")
		return
	}

	total := myWeight + partnerWeight
	pctMe := 50
	if total > 0 {
		pctMe = (100*myWeight + total/2) / total // round(100*my/total)
	}

	type section struct {
		Key   string     `json:"key"`
		Label string     `json:"label"`
		Tasks []TaskJSON `json:"tasks"`
	}
	sections := []section{
		{Key: "chore", Label: "CHORES — TODAY", Tasks: []TaskJSON{}},
		{Key: "admin", Label: "THE ADMIN", Tasks: []TaskJSON{}},
	}
	trows, err := a.DB.Query(ctx, `
		select `+taskCols+` from tasks t
		left join completions c on c.task_id = t.id and c.week_id = $1
		left join recurring_completions rc on rc.task_id = t.id and rc.occurrence_on = $2
		where t.household_id = $3 and t.archived_at is null`+visibleTodayRecurrence+`
		order by t.created_at`, m.WeekID, today(), m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "summary failed")
		return
	}
	defer trows.Close()
	for trows.Next() {
		t, err := scanTask(trows)
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal", "summary failed")
			return
		}
		if t.Section == "chore" {
			sections[0].Tasks = append(sections[0].Tasks, t)
		} else {
			sections[1].Tasks = append(sections[1].Tasks, t)
		}
	}
	if trows.Err() != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "summary failed")
		return
	}

	var pendingDrafts int
	if err := a.DB.QueryRow(ctx, `
		select count(*) from drafts
		where household_id = $1 and status = 'pending'`, m.HouseholdID).Scan(&pendingDrafts); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "summary failed")
		return
	}

	partnerName := m.PartnerName
	if partnerName == "" {
		partnerName = "your partner"
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"week":                WeekJSON{ID: m.WeekID, Index: m.WeekIndex, StartedOn: dateStr(m.WeekStart)},
		"pebbles":             pebbles,
		"percent_me":          pctMe,
		"percent_partner":     100 - pctMe,
		"caption":             beamCaption(total, pctMe, m.DisplayName, partnerName),
		"sections":            sections,
		"pending_draft_count": pendingDrafts,
	})
}
