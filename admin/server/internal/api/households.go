package api

import (
	"crypto/rand"
	"errors"
	"math/big"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

type householdRow struct {
	ID            string  `json:"id"`
	Name          string  `json:"name"`
	InviteCode    string  `json:"invite_code"`
	CreatedAt     string  `json:"created_at"`
	ActiveMembers int     `json:"active_members"`
	DepartedCount int     `json:"departed_members"`
	OpenTasks     int     `json:"open_tasks"`
	PendingDrafts int     `json:"pending_drafts"`
	GoogleLinked  int     `json:"google_accounts"`
	PendingInvite *string `json:"pending_invite_email"`
	CalendarID    string  `json:"calendar_id"`
	LastActivity  *string `json:"last_activity_at"`
	SyncIssues    int     `json:"calendar_sync_issues"`
}

// ListHouseholds is the households table. `last_activity_at` is the newest of
// the things that actually mean "someone used the app here" — a household with
// a fresh row and no activity is what a stalled onboarding looks like.
func (a *API) ListHouseholds(w http.ResponseWriter, r *http.Request) {
	p := readPage(r)
	pattern := p.like()

	const from = `
		from households h
		 where $1 = '%'
		    or h.name ilike $1
		    or h.id::text ilike $1
		    or h.invite_code ilike $1
		    or exists (select 1 from members m
		                where m.household_id = h.id and m.display_name ilike $1)`

	var total int
	if err := a.DB.QueryRow(r.Context(), `select count(*) `+from, pattern).Scan(&total); err != nil {
		fail(w, "count households", err)
		return
	}
	rows, err := a.DB.Query(r.Context(), `
		select h.id::text, h.name, h.invite_code, h.created_at, h.calendar_id,
		       (select count(*) from members m where m.household_id = h.id and m.left_at is null),
		       (select count(*) from members m where m.household_id = h.id and m.left_at is not null),
		       (select count(*) from tasks t where t.household_id = h.id and t.archived_at is null),
		       (select count(*) from drafts d where d.household_id = h.id and d.status = 'pending'),
		       (select count(*) from google_accounts g where g.household_id = h.id),
		       (select i.email from household_invites i
		         where i.household_id = h.id and i.status = 'pending' limit 1),
		       (select count(*) from tasks t where t.household_id = h.id and t.archived_at is null
		         and t.calendar_sync_state in ('retry_required','external_deleted','external_changed')),
		       greatest(
		         (select max(t.created_at) from tasks t where t.household_id = h.id),
		         (select max(c.completed_at) from completions c
		            join tasks t on t.id = c.task_id where t.household_id = h.id),
		         (select max(rc.completed_at) from recurring_completions rc
		            join tasks t on t.id = rc.task_id where t.household_id = h.id),
		         (select max(d.created_at) from drafts d where d.household_id = h.id))
		  `+from+`
		 order by h.created_at desc
		 limit $2 offset $3`, pattern, p.Limit, p.Offset)
	if err != nil {
		fail(w, "list households", err)
		return
	}
	defer rows.Close()

	out := []householdRow{}
	for rows.Next() {
		var h householdRow
		var created time.Time
		var last *time.Time
		if err := rows.Scan(&h.ID, &h.Name, &h.InviteCode, &created, &h.CalendarID,
			&h.ActiveMembers, &h.DepartedCount, &h.OpenTasks, &h.PendingDrafts,
			&h.GoogleLinked, &h.PendingInvite, &h.SyncIssues, &last); err != nil {
			fail(w, "scan household", err)
			return
		}
		h.CreatedAt = created.UTC().Format(time.RFC3339)
		h.LastActivity = tsPtr(last)
		out = append(out, h)
	}
	if err := rows.Err(); err != nil {
		fail(w, "iterate households", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"rows": out, "page": p.meta(total)})
}

// ---------------------------------------------------------------- detail

type memberRow struct {
	ID           string  `json:"id"`
	UserID       string  `json:"user_id"`
	Email        *string `json:"email"`
	DisplayName  string  `json:"display_name"`
	Color        string  `json:"color"`
	HasAvatar    bool    `json:"has_avatar"`
	JoinedAt     string  `json:"joined_at"`
	LeftAt       *string `json:"left_at"`
	GoogleEmail  *string `json:"google_email"`
	GoogleSyncAt *string `json:"google_last_sync_at"`
	GoogleCount  int     `json:"google_last_sync_count"`
	CalListed    *string `json:"calendar_listed_at"`
	IsCalOwner   bool    `json:"is_calendar_owner"`
	Drafts       int     `json:"drafts_total"`
	Completions  int     `json:"completions"`
}

type weekRow struct {
	ID          string  `json:"id"`
	Index       int     `json:"index"`
	StartedOn   string  `json:"started_on"`
	ClosedAt    *string `json:"closed_at"`
	Completions int     `json:"completions"`
}

type taskRow struct {
	ID           string  `json:"id"`
	Title        string  `json:"title"`
	Section      string  `json:"section"`
	Weight       int     `json:"weight"`
	Recurrence   string  `json:"recurrence"`
	DueOn        *string `json:"due_on"`
	DueTime      *string `json:"due_time"`
	OwnerName    string  `json:"owner_name"`
	OwnerID      string  `json:"owner_member_id"`
	Archived     *string `json:"archived_at"`
	CreatedAt    string  `json:"created_at"`
	SyncState    string  `json:"calendar_sync_state"`
	SyncedAt     *string `json:"calendar_last_synced_at"`
	SyncError    *string `json:"calendar_last_error"`
	EventURL     *string `json:"google_event_url"`
	OriginLabel  *string `json:"origin_label"`
	DoneThisWeek bool    `json:"done_in_open_week"`
}

type inviteRow struct {
	ID            string  `json:"id"`
	HouseholdID   string  `json:"household_id"`
	HouseholdName string  `json:"household_name"`
	Email         string  `json:"email"`
	Status        string  `json:"status"`
	InvitedBy     string  `json:"invited_by"`
	CreatedAt     string  `json:"created_at"`
	RespondedAt   *string `json:"responded_at"`
}

type moneyRow struct {
	ID       string  `json:"id"`
	Kind     string  `json:"kind"` // "expense" | "settlement"
	Title    string  `json:"title"`
	Cents    int64   `json:"amount_cents"`
	Who      string  `json:"who"`
	When     string  `json:"when"`
	Settled  bool    `json:"settled"`
	Counter  *string `json:"counterparty"`
}

type householdDetail struct {
	Household householdRow  `json:"household"`
	Members   []memberRow   `json:"members"`
	Weeks     []weekRow     `json:"weeks"`
	Tasks     []taskRow     `json:"tasks"`
	Invites   []inviteRow   `json:"invites"`
	Money     []moneyRow    `json:"money"`
	Activity  []activityRow `json:"activity"`
	Calendar  calendarInfo  `json:"calendar"`
}

type calendarInfo struct {
	CalendarID    string  `json:"calendar_id"`
	OwnerMemberID *string `json:"owner_member_id"`
	OwnerName     *string `json:"owner_name"`
	LastSyncAt    *string `json:"last_sync_at"`
	Synced        int     `json:"synced"`
	Retry         int     `json:"retry_required"`
	ExternalGone  int     `json:"external_deleted"`
	ExternalEdit  int     `json:"external_changed"`
	NotScheduled  int     `json:"not_scheduled"`
}

// GetHousehold is the household page. It is a fan of small queries rather than
// one join: the joins would multiply rows across members × tasks × weeks and
// the de-duplication would cost more than the extra round trips.
func (a *API) GetHousehold(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ctx := r.Context()
	var d householdDetail

	var created time.Time
	var lastActivity, calSync *time.Time
	err := a.DB.QueryRow(ctx, `
		select h.id::text, h.name, h.invite_code, h.created_at, h.calendar_id,
		       h.calendar_owner_member_id::text, h.calendar_last_sync_at,
		       (select count(*) from members m where m.household_id = h.id and m.left_at is null),
		       (select count(*) from members m where m.household_id = h.id and m.left_at is not null),
		       (select count(*) from tasks t where t.household_id = h.id and t.archived_at is null),
		       (select count(*) from drafts dd where dd.household_id = h.id and dd.status = 'pending'),
		       (select count(*) from google_accounts g where g.household_id = h.id),
		       (select i.email from household_invites i
		         where i.household_id = h.id and i.status = 'pending' limit 1),
		       (select count(*) from tasks t where t.household_id = h.id and t.archived_at is null
		         and t.calendar_sync_state in ('retry_required','external_deleted','external_changed')),
		       greatest(
		         (select max(t.created_at) from tasks t where t.household_id = h.id),
		         (select max(dd.created_at) from drafts dd where dd.household_id = h.id))
		  from households h where h.id::text = $1`, id).
		Scan(&d.Household.ID, &d.Household.Name, &d.Household.InviteCode, &created,
			&d.Household.CalendarID, &d.Calendar.OwnerMemberID, &calSync,
			&d.Household.ActiveMembers, &d.Household.DepartedCount, &d.Household.OpenTasks,
			&d.Household.PendingDrafts, &d.Household.GoogleLinked, &d.Household.PendingInvite,
			&d.Household.SyncIssues, &lastActivity)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "not_found", "No household with that id.")
		return
	}
	if err != nil {
		fail(w, "load household", err)
		return
	}
	d.Household.CreatedAt = created.UTC().Format(time.RFC3339)
	d.Household.LastActivity = tsPtr(lastActivity)
	d.Calendar.CalendarID = d.Household.CalendarID
	d.Calendar.LastSyncAt = tsPtr(calSync)

	// members ---------------------------------------------------------------
	rows, err := a.DB.Query(ctx, `
		select m.id::text, m.user_id::text, u.email, m.display_name, m.color,
		       (m.avatar_path is not null), m.created_at, m.left_at,
		       g.email, g.last_sync_at, coalesce(g.last_sync_count,0), g.calendar_listed_at,
		       (h.calendar_owner_member_id = m.id),
		       (select count(*) from drafts dd where dd.source_member_id = m.id),
		       (select count(*) from completions c where c.member_id = m.id)
		         + (select count(*) from recurring_completions rc where rc.member_id = m.id)
		  from members m
		  join households h on h.id = m.household_id
		  left join auth.users u on u.id = m.user_id
		  left join google_accounts g on g.member_id = m.id
		 where m.household_id::text = $1
		 order by m.left_at nulls first, m.created_at`, id)
	if err != nil {
		fail(w, "load members", err)
		return
	}
	d.Members = []memberRow{}
	for rows.Next() {
		var m memberRow
		var joined time.Time
		var left, sync, listed *time.Time
		var owner *bool
		if err := rows.Scan(&m.ID, &m.UserID, &m.Email, &m.DisplayName, &m.Color, &m.HasAvatar,
			&joined, &left, &m.GoogleEmail, &sync, &m.GoogleCount, &listed, &owner,
			&m.Drafts, &m.Completions); err != nil {
			rows.Close()
			fail(w, "scan member", err)
			return
		}
		m.JoinedAt = joined.UTC().Format(time.RFC3339)
		m.LeftAt, m.GoogleSyncAt, m.CalListed = tsPtr(left), tsPtr(sync), tsPtr(listed)
		m.IsCalOwner = owner != nil && *owner
		if m.IsCalOwner {
			name := m.DisplayName
			d.Calendar.OwnerName = &name
		}
		d.Members = append(d.Members, m)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fail(w, "iterate members", err)
		return
	}

	// weeks -----------------------------------------------------------------
	rows, err = a.DB.Query(ctx, `
		select w.id::text, w.week_index, w.started_on, w.closed_at,
		       (select count(*) from completions c where c.week_id = w.id)
		  from weeks w where w.household_id::text = $1
		 order by w.week_index desc limit 30`, id)
	if err != nil {
		fail(w, "load weeks", err)
		return
	}
	d.Weeks = []weekRow{}
	for rows.Next() {
		var wk weekRow
		var started time.Time
		var closed *time.Time
		if err := rows.Scan(&wk.ID, &wk.Index, &started, &closed, &wk.Completions); err != nil {
			rows.Close()
			fail(w, "scan week", err)
			return
		}
		wk.StartedOn = started.Format("2006-01-02")
		wk.ClosedAt = tsPtr(closed)
		d.Weeks = append(d.Weeks, wk)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fail(w, "iterate weeks", err)
		return
	}

	// tasks -----------------------------------------------------------------
	rows, err = a.DB.Query(ctx, `
		-- due_time is a bare SQL time; render it as text here rather than
		-- teaching the driver a type the JSON contract does not need.
		select t.id::text, t.title, t.section, t.weight, t.recurrence, t.due_on,
		       to_char(t.due_time, 'HH24:MI'),
		       t.owner_member_id::text, om.display_name, t.archived_at, t.created_at,
		       t.calendar_sync_state, t.calendar_last_synced_at, t.calendar_last_error,
		       t.google_event_url, t.origin_label,
		       exists (select 1 from completions c
		                 join weeks w on w.id = c.week_id
		                where c.task_id = t.id and w.household_id = t.household_id
		                  and w.closed_at is null)
		  from tasks t
		  join members om on om.id = t.owner_member_id
		 where t.household_id::text = $1
		 order by t.archived_at nulls first, t.created_at desc
		 limit 300`, id)
	if err != nil {
		fail(w, "load tasks", err)
		return
	}
	d.Tasks = []taskRow{}
	for rows.Next() {
		var t taskRow
		var due, archived *time.Time
		var createdAt time.Time
		var syncedAt *time.Time
		var dueTime *string
		if err := rows.Scan(&t.ID, &t.Title, &t.Section, &t.Weight, &t.Recurrence, &due, &dueTime,
			&t.OwnerID, &t.OwnerName, &archived, &createdAt, &t.SyncState, &syncedAt,
			&t.SyncError, &t.EventURL, &t.OriginLabel, &t.DoneThisWeek); err != nil {
			rows.Close()
			fail(w, "scan task", err)
			return
		}
		t.DueOn, t.DueTime = dateOnly(due), dueTime
		t.Archived, t.SyncedAt = tsPtr(archived), tsPtr(syncedAt)
		t.CreatedAt = createdAt.UTC().Format(time.RFC3339)
		switch t.SyncState {
		case "synced":
			d.Calendar.Synced++
		case "retry_required":
			d.Calendar.Retry++
		case "external_deleted":
			d.Calendar.ExternalGone++
		case "external_changed":
			d.Calendar.ExternalEdit++
		default:
			d.Calendar.NotScheduled++
		}
		d.Tasks = append(d.Tasks, t)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fail(w, "iterate tasks", err)
		return
	}

	// invites ---------------------------------------------------------------
	d.Invites, err = a.invitesForHousehold(r, id)
	if err != nil {
		fail(w, "load invites", err)
		return
	}

	// money -----------------------------------------------------------------
	rows, err = a.DB.Query(ctx, `
		select id, kind, title, cents, who, at, settled, counterparty from (
		  select e.id::text as id, 'expense' as kind, e.title, e.amount_cents as cents,
		         pm.display_name as who, e.incurred_on::timestamptz as at,
		         (e.settlement_id is not null) as settled, null::text as counterparty
		    from expenses e join members pm on pm.id = e.paid_by_member_id
		   where e.household_id::text = $1
		  union all
		  select s.id::text, 'settlement', 'Settle up', s.amount_cents,
		         fm.display_name, s.created_at, true, tm.display_name
		    from settlements s
		    join members fm on fm.id = s.from_member_id
		    join members tm on tm.id = s.to_member_id
		   where s.household_id::text = $1
		) m order by at desc limit 60`, id)
	if err != nil {
		fail(w, "load money", err)
		return
	}
	d.Money = []moneyRow{}
	for rows.Next() {
		var m moneyRow
		var at time.Time
		if err := rows.Scan(&m.ID, &m.Kind, &m.Title, &m.Cents, &m.Who, &at, &m.Settled, &m.Counter); err != nil {
			rows.Close()
			fail(w, "scan money", err)
			return
		}
		m.When = at.UTC().Format(time.RFC3339)
		d.Money = append(d.Money, m)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		fail(w, "iterate money", err)
		return
	}

	d.Activity, err = a.householdActivity(r, id)
	if err != nil {
		fail(w, "household activity", err)
		return
	}
	writeJSON(w, http.StatusOK, d)
}

func (a *API) householdActivity(r *http.Request, id string) ([]activityRow, error) {
	rows, err := a.DB.Query(r.Context(), `
		select at, kind, title, who from (
		  select t.created_at as at, 'task.created' as kind, t.title,
		         coalesce(cb.display_name, om.display_name) as who
		    from tasks t
		    left join members cb on cb.id = t.created_by
		    join members om on om.id = t.owner_member_id
		   where t.household_id::text = $1
		  union all
		  select c.completed_at, 'task.completed', t.title, m.display_name
		    from completions c join tasks t on t.id = c.task_id
		    join members m on m.id = c.member_id
		   where t.household_id::text = $1
		  union all
		  select rc.completed_at, 'task.completed', t.title, m.display_name
		    from recurring_completions rc join tasks t on t.id = rc.task_id
		    join members m on m.id = rc.member_id
		   where t.household_id::text = $1
		  union all
		  select d.created_at, 'draft.' || d.status, d.title, m.display_name
		    from drafts d join members m on m.id = d.source_member_id
		   where d.household_id::text = $1
		  union all
		  select e.created_at, 'expense.added', e.title, m.display_name
		    from expenses e join members m on m.id = e.paid_by_member_id
		   where e.household_id::text = $1
		  union all
		  select s.created_at, 'settlement.recorded', 'Settle up', m.display_name
		    from settlements s join members m on m.id = s.from_member_id
		   where s.household_id::text = $1
		  union all
		  select m2.created_at, 'member.joined', m2.display_name, m2.display_name
		    from members m2 where m2.household_id::text = $1
		  union all
		  select m3.left_at, 'member.left', m3.display_name, m3.display_name
		    from members m3 where m3.household_id::text = $1 and m3.left_at is not null
		) feed order by at desc limit 60`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []activityRow{}
	for rows.Next() {
		var e activityRow
		var at time.Time
		if err := rows.Scan(&at, &e.Kind, &e.Title, &e.Where); err != nil {
			return nil, err
		}
		e.At = at.UTC().Format(time.RFC3339)
		out = append(out, e)
	}
	return out, rows.Err()
}

func (a *API) invitesForHousehold(r *http.Request, id string) ([]inviteRow, error) {
	return a.scanInvites(r, `where i.household_id::text = $1`, id)
}

func (a *API) invitesForEmail(r *http.Request, email string) ([]inviteRow, error) {
	return a.scanInvites(r, `where lower(i.email) = lower($1)`, email)
}

func (a *API) scanInvites(r *http.Request, where, arg string) ([]inviteRow, error) {
	rows, err := a.DB.Query(r.Context(), `
		select i.id::text, i.household_id::text, h.name, i.email, i.status,
		       ib.display_name, i.created_at, i.responded_at
		  from household_invites i
		  join households h on h.id = i.household_id
		  join members ib on ib.id = i.invited_by_member_id
		  `+where+`
		 order by i.created_at desc`, arg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []inviteRow{}
	for rows.Next() {
		var i inviteRow
		var created time.Time
		var responded *time.Time
		if err := rows.Scan(&i.ID, &i.HouseholdID, &i.HouseholdName, &i.Email, &i.Status,
			&i.InvitedBy, &created, &responded); err != nil {
			return nil, err
		}
		i.CreatedAt = created.UTC().Format(time.RFC3339)
		i.RespondedAt = tsPtr(responded)
		out = append(out, i)
	}
	return out, rows.Err()
}

// ---------------------------------------------------------------- writes

// RevokeInvite closes a pending email invite. It is the mirror of the owner
// pressing "cancel" in the app, done for them when they cannot — so it only
// touches a row that is still pending, and says so when there is nothing to do.
func (a *API) RevokeInvite(w http.ResponseWriter, r *http.Request) {
	householdID := chi.URLParam(r, "id")
	inviteID := chi.URLParam(r, "inviteID")

	var email, status string
	err := a.DB.QueryRow(r.Context(), `
		select email, status from household_invites
		 where id::text = $1 and household_id::text = $2`, inviteID, householdID).
		Scan(&email, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "not_found", "No such invite in this household.")
		return
	}
	if err != nil {
		fail(w, "load invite", err)
		return
	}
	if status != "pending" {
		writeErr(w, http.StatusConflict, "not_pending",
			"That invite is already "+status+" — there is nothing to revoke.")
		return
	}
	if _, err := a.DB.Exec(r.Context(), `
		update household_invites set status = 'revoked', responded_at = now()
		 where id::text = $1 and status = 'pending'`, inviteID); err != nil {
		fail(w, "revoke invite", err)
		return
	}
	a.audit(r, auditEntry{
		Action: "household.invite.revoke", TargetType: "household", TargetID: householdID,
		Summary: "Revoked pending invite to " + email,
		Before:  map[string]any{"invite_id": inviteID, "email": email, "status": status},
		After:   map[string]any{"invite_id": inviteID, "email": email, "status": "revoked"},
	})
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "invite_id": inviteID, "status": "revoked"})
}

// inviteCodeAlphabet drops the characters people mistype when reading a code
// off a screen: 0/O, 1/I/L. Six characters from 26 is ~300M combinations, and
// the column is unique, so a collision is retried rather than tolerated.
const inviteCodeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

// RegenerateInviteCode issues a new join code, invalidating the old one. This
// is the answer to "our code leaked" — the previous value is recorded in the
// audit row so support can recognise the dead code if someone quotes it.
func (a *API) RegenerateInviteCode(w http.ResponseWriter, r *http.Request) {
	householdID := chi.URLParam(r, "id")

	var name, oldCode string
	err := a.DB.QueryRow(r.Context(),
		`select name, invite_code from households where id::text = $1`, householdID).
		Scan(&name, &oldCode)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "not_found", "No household with that id.")
		return
	}
	if err != nil {
		fail(w, "load household", err)
		return
	}

	var newCode string
	for attempt := 0; attempt < 8; attempt++ {
		candidate, err := randomCode(6)
		if err != nil {
			fail(w, "mint code", err)
			return
		}
		tag, err := a.DB.Exec(r.Context(), `
			update households set invite_code = $2
			 where id::text = $1
			   and not exists (select 1 from households o where o.invite_code = $2)`,
			householdID, candidate)
		if err != nil {
			fail(w, "write code", err)
			return
		}
		if tag.RowsAffected() == 1 {
			newCode = candidate
			break
		}
	}
	if newCode == "" {
		writeErr(w, http.StatusConflict, "code_collision",
			"Could not find a free invite code. Try again.")
		return
	}
	a.audit(r, auditEntry{
		Action: "household.invite_code.regenerate", TargetType: "household", TargetID: householdID,
		Summary: "Regenerated invite code for " + name,
		Before:  map[string]any{"invite_code": oldCode},
		After:   map[string]any{"invite_code": newCode},
	})
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "invite_code": newCode})
}

func randomCode(n int) (string, error) {
	out := make([]byte, n)
	limit := big.NewInt(int64(len(inviteCodeAlphabet)))
	for i := range out {
		idx, err := rand.Int(rand.Reader, limit)
		if err != nil {
			return "", err
		}
		out[i] = inviteCodeAlphabet[idx.Int64()]
	}
	return string(out), nil
}
