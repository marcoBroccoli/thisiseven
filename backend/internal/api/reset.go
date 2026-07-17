package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

func pctPair(me, partner int64) (int, int) {
	total := me + partner
	if total == 0 {
		return 50, 50
	}
	p := int((100*me + total/2) / total)
	return p, 100 - p
}

// GET /v1/reset — everything the Sunday ritual needs.
func (a *API) Reset(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	ctx := r.Context()

	// Completion weight by section for the open week.
	var choreMe, choreP, adminMe, adminP int64
	rows, err := a.DB.Query(ctx, `
		select t.section, c.member_id, coalesce(sum(c.weight), 0)
		from completions c join tasks t on t.id = c.task_id
		where c.week_id = $1 group by t.section, c.member_id`, m.WeekID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
		return
	}
	for rows.Next() {
		var section, member string
		var sum int64
		if err := rows.Scan(&section, &member, &sum); err != nil {
			rows.Close()
			httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
			return
		}
		mine := member == m.MemberID
		switch {
		case section == "chore" && mine:
			choreMe = sum
		case section == "chore":
			choreP = sum
		case mine:
			adminMe = sum
		default:
			adminP = sum
		}
	}
	rows.Close()
	if rows.Err() != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
		return
	}

	// Money fronted during this week (any settlement state).
	var moneyMe, moneyP int64
	mrows, err := a.DB.Query(ctx, `
		select paid_by_member_id, coalesce(sum(amount_cents), 0)
		from expenses where household_id = $1 and incurred_on >= $2
		group by paid_by_member_id`, m.HouseholdID, m.WeekStart)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
		return
	}
	for mrows.Next() {
		var member string
		var sum int64
		if err := mrows.Scan(&member, &sum); err != nil {
			mrows.Close()
			httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
			return
		}
		if member == m.MemberID {
			moneyMe = sum
		} else {
			moneyP = sum
		}
	}
	mrows.Close()
	if mrows.Err() != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
		return
	}

	type row struct {
		Key        string `json:"key"`
		Label      string `json:"label"`
		MePct      int    `json:"me_pct"`
		PartnerPct int    `json:"partner_pct"`
	}
	cMe, cP := pctPair(choreMe, choreP)
	aMe, aP := pctPair(adminMe, adminP)
	mMe, mP := pctPair(moneyMe, moneyP)
	rowsOut := []row{
		{"chores", "Chores", cMe, cP},
		{"admin", "The admin", aMe, aP},
		{"money", "Money fronted", mMe, mP},
	}

	partnerName := m.PartnerName
	if partnerName == "" {
		partnerName = "your partner"
	}
	biggest := biggestCarry(m.DisplayName, partnerName,
		choreMe, choreP, adminMe, adminP, moneyMe, moneyP)

	apps := []AppreciationJSON{}
	arows, err := a.DB.Query(ctx, `
		select id, from_member_id, to_member_id, body, said
		from appreciations where week_id = $1 order by created_at`, m.WeekID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
		return
	}
	for arows.Next() {
		var ap AppreciationJSON
		if err := arows.Scan(&ap.ID, &ap.FromMemberID, &ap.ToMemberID, &ap.Body, &ap.Said); err != nil {
			arows.Close()
			httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
			return
		}
		apps = append(apps, ap)
	}
	arows.Close()

	trades := []TradeJSON{}
	trows, err := a.DB.Query(ctx, `
		select tr.id, tr.task_id, t.title, tr.from_member_id, tr.to_member_id, tr.accepted
		from trades tr join tasks t on t.id = tr.task_id
		where tr.week_id = $1 order by tr.created_at`, m.WeekID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
		return
	}
	for trows.Next() {
		var t TradeJSON
		if err := trows.Scan(&t.ID, &t.TaskID, &t.TaskTitle, &t.FromMemberID, &t.ToMemberID, &t.Accepted); err != nil {
			trows.Close()
			httpx.Error(w, http.StatusInternalServerError, "internal", "reset lookup failed")
			return
		}
		trades = append(trades, t)
	}
	trows.Close()

	httpx.JSON(w, http.StatusOK, map[string]any{
		"week":          WeekJSON{ID: m.WeekID, Index: m.WeekIndex, StartedOn: dateStr(m.WeekStart)},
		"rows":          rowsOut,
		"biggest_carry": biggest,
		"appreciations": apps,
		"trades":        trades,
	})
}

// biggestCarry names the week's single largest contribution.
func biggestCarry(myName, partnerName string,
	choreMe, choreP, adminMe, adminP, moneyMe, moneyP int64) string {

	name := func(mine bool) string {
		if mine {
			return myName
		}
		return partnerName
	}
	type cand struct {
		share    int
		sentence string
	}
	var cands []cand
	if t := choreMe + choreP; t > 0 {
		me := choreMe >= choreP
		p, _ := pctPair(max64(choreMe, choreP), min64(choreMe, choreP))
		cands = append(cands, cand{p, fmt.Sprintf(
			"%s did the heavy lifting on chores — %d%% by weight.", name(me), p)})
	}
	if t := adminMe + adminP; t > 0 {
		me := adminMe >= adminP
		p, _ := pctPair(max64(adminMe, adminP), min64(adminMe, adminP))
		cands = append(cands, cand{p, fmt.Sprintf(
			"%s carried the admin — %d%% of the remembering.", name(me), p)})
	}
	if t := moneyMe + moneyP; t > 0 {
		me := moneyMe >= moneyP
		p, _ := pctPair(max64(moneyMe, moneyP), min64(moneyMe, moneyP))
		cands = append(cands, cand{p, fmt.Sprintf(
			"%s fronted most of the money — %s of %s.", name(me),
			euros(max64(moneyMe, moneyP)), euros(t))})
	}
	if len(cands) == 0 {
		return "A quiet week. Nothing carried, nothing owed."
	}
	best := cands[0]
	for _, c := range cands[1:] {
		if c.share > best.share {
			best = c
		}
	}
	return best.sentence
}

func max64(a, b int64) int64 { if a > b { return a }; return b }
func min64(a, b int64) int64 { if a < b { return a }; return b }

// PUT /v1/appreciations/mine — upsert my kind thing for the open week.
func (a *API) PutAppreciation(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !m.requirePartner(w) {
		return
	}
	var in struct {
		Body *string `json:"body"`
		Said bool    `json:"said"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	var ap AppreciationJSON
	err := a.DB.QueryRow(r.Context(), `
		insert into appreciations (week_id, from_member_id, to_member_id, body, said)
		values ($1, $2, $3, $4, $5)
		on conflict (week_id, from_member_id)
		do update set body = excluded.body, said = excluded.said
		returning id, from_member_id, to_member_id, body, said`,
		m.WeekID, m.MemberID, m.PartnerID, in.Body, in.Said).
		Scan(&ap.ID, &ap.FromMemberID, &ap.ToMemberID, &ap.Body, &ap.Said)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not save appreciation")
		return
	}
	httpx.JSON(w, http.StatusOK, ap)
}

func (a *API) fetchTrade(r *http.Request, m *Membership, id string) (TradeJSON, error) {
	var t TradeJSON
	err := a.DB.QueryRow(r.Context(), `
		select tr.id, tr.task_id, t.title, tr.from_member_id, tr.to_member_id, tr.accepted
		from trades tr join tasks t on t.id = tr.task_id
		where tr.id = $1 and tr.household_id = $2`, id, m.HouseholdID).
		Scan(&t.ID, &t.TaskID, &t.TaskTitle, &t.FromMemberID, &t.ToMemberID, &t.Accepted)
	return t, err
}

// POST /v1/trades {task_id} — hand a task across the table for next week.
func (a *API) CreateTrade(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !m.requirePartner(w) {
		return
	}
	var in struct {
		TaskID string `json:"task_id"`
	}
	if !httpx.Decode(w, r, &in) || in.TaskID == "" {
		if in.TaskID == "" {
			httpx.Error(w, http.StatusBadRequest, "missing_fields", "task_id is required")
		}
		return
	}
	var owner string
	err := a.DB.QueryRow(r.Context(), `
		select owner_member_id from tasks
		where id = $1 and household_id = $2 and archived_at is null`,
		in.TaskID, m.HouseholdID).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such task")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "trade failed")
		return
	}
	to := m.PartnerID
	if owner == m.PartnerID {
		to = m.MemberID
	}
	var id string
	err = a.DB.QueryRow(r.Context(), `
		insert into trades (household_id, week_id, task_id, from_member_id, to_member_id, proposed_by)
		values ($1, $2, $3, $4, $5, $6)
		on conflict (week_id, task_id) do nothing returning id`,
		m.HouseholdID, m.WeekID, in.TaskID, owner, to, m.MemberID).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusConflict, "trade_exists", "that task is already on the table")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "trade failed")
		return
	}
	t, err := a.fetchTrade(r, m, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusCreated, t)
}

// POST /v1/trades/{id}/accept {accepted} — only the side receiving the
// proposal (i.e. not the proposer) can accept it.
func (a *API) AcceptTrade(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	var in struct {
		Accepted bool `json:"accepted"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	id := chi.URLParam(r, "id")
	var proposedBy string
	err := a.DB.QueryRow(r.Context(), `
		select proposed_by from trades
		where id = $1 and household_id = $2 and applied_at is null`,
		id, m.HouseholdID).Scan(&proposedBy)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such trade")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "trade lookup failed")
		return
	}
	if proposedBy == m.MemberID {
		httpx.Error(w, http.StatusConflict, "own_trade", "your partner has to accept this one")
		return
	}
	if _, err := a.DB.Exec(r.Context(),
		`update trades set accepted = $1 where id = $2`, in.Accepted, id); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not update trade")
		return
	}
	t, err := a.fetchTrade(r, m, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, t)
}

// DELETE /v1/trades/{id}
func (a *API) DeleteTrade(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	tag, err := a.DB.Exec(r.Context(), `
		delete from trades where id = $1 and household_id = $2 and applied_at is null`,
		chi.URLParam(r, "id"), m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not delete trade")
		return
	}
	if tag.RowsAffected() == 0 {
		httpx.Error(w, http.StatusNotFound, "not_found", "no such trade")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// POST /v1/week/close — the pour. One transaction: accepted trades applied,
// finished one-offs archived, week closed, next week opened level.
// Optional {week_id} guards against double-taps closing two weeks.
func (a *API) CloseWeek(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	var in struct {
		WeekID *string `json:"week_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&in) // empty body is fine

	var closed, next WeekJSON
	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		if err := lockHousehold(r.Context(), tx, m.HouseholdID); err != nil {
			return err
		}
		var weekID string
		var weekIndex int
		if err := tx.QueryRow(r.Context(), `
			select id, week_index from weeks
			where household_id = $1 and closed_at is null`, m.HouseholdID).
			Scan(&weekID, &weekIndex); err != nil {
			return err
		}
		if in.WeekID != nil && *in.WeekID != weekID {
			return errWeekAlreadyClosed
		}
		// Apply accepted trades: the task changes hands.
		if _, err := tx.Exec(r.Context(), `
			update tasks t set owner_member_id = tr.to_member_id
			from trades tr
			where tr.task_id = t.id and tr.week_id = $1
			  and tr.accepted and tr.applied_at is null`, weekID); err != nil {
			return err
		}
		if _, err := tx.Exec(r.Context(), `
			update trades set applied_at = now()
			where week_id = $1 and accepted and applied_at is null`, weekID); err != nil {
			return err
		}
		// One-off tasks that got done this week retire with the week.
		if _, err := tx.Exec(r.Context(), `
			update tasks set archived_at = now()
			where household_id = $1 and recurrence = 'none' and archived_at is null
			  and id in (select task_id from completions where week_id = $2)`,
			m.HouseholdID, weekID); err != nil {
			return err
		}
		var closedOn string
		if err := tx.QueryRow(r.Context(), `
			update weeks set closed_at = now() where id = $1
			returning started_on::text`, weekID).Scan(&closedOn); err != nil {
			return err
		}
		closed = WeekJSON{ID: weekID, Index: weekIndex, StartedOn: closedOn}
		closed.ClosedAt = strPtr(time.Now().UTC().Format(time.RFC3339))
		return tx.QueryRow(r.Context(), `
			insert into weeks (household_id, week_index, started_on)
			values ($1, $2, $3) returning id, week_index, started_on::text`,
			m.HouseholdID, weekIndex+1, today()).
			Scan(&next.ID, &next.Index, &next.StartedOn)
	})
	if errors.Is(err, errWeekAlreadyClosed) {
		httpx.Error(w, http.StatusConflict, "week_already_closed", "that week was already poured out")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not close the week")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"closed_week": closed, "new_week": next})
}

var errWeekAlreadyClosed = errors.New("week already closed")
