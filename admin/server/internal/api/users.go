package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// A "user" in the console is a GoTrue identity (auth.users) plus whatever
// membership rows it owns. Evend has no user table of its own — members.user_id
// is the only link — so every user view starts in the auth schema and joins out.

type userRow struct {
	ID             string  `json:"id"`
	Email          *string `json:"email"`
	CreatedAt      string  `json:"created_at"`
	LastSignInAt   *string `json:"last_sign_in_at"`
	Provider       *string `json:"provider"`
	Confirmed      bool    `json:"confirmed"`
	HouseholdCount int     `json:"household_count"`
	ActiveCount    int     `json:"active_membership_count"`
	DisplayName    *string `json:"display_name"`
	LastActivityAt *string `json:"last_activity_at"`
}

// ListUsers powers the users table: one row per auth identity, searchable by
// email, id or any display name they use in a household.
func (a *API) ListUsers(w http.ResponseWriter, r *http.Request) {
	p := readPage(r)
	pattern := p.like()

	const from = `
		from auth.users u
		 where $1 = '%'
		    or coalesce(u.email,'') ilike $1
		    or u.id::text ilike $1
		    or exists (select 1 from members m
		                where m.user_id = u.id and m.display_name ilike $1)`

	var total int
	if err := a.DB.QueryRow(r.Context(), `select count(*) `+from, pattern).Scan(&total); err != nil {
		fail(w, "count users", err)
		return
	}

	rows, err := a.DB.Query(r.Context(), `
		select u.id::text,
		       u.email,
		       coalesce(u.created_at, now()),
		       u.last_sign_in_at,
		       nullif(u.raw_app_meta_data->>'provider', ''),
		       (u.confirmed_at is not null) as confirmed,
		       (select count(*) from members m where m.user_id = u.id),
		       (select count(*) from members m where m.user_id = u.id and m.left_at is null),
		       (select m.display_name from members m
		         where m.user_id = u.id order by m.left_at nulls first, m.created_at desc limit 1),
		       greatest(
		         u.last_sign_in_at,
		         (select max(t.created_at) from tasks t
		            join members m on m.id = t.created_by where m.user_id = u.id),
		         (select max(d.created_at) from drafts d
		            join members m on m.id = d.source_member_id where m.user_id = u.id)
		       )
		  `+from+`
		 order by u.created_at desc
		 limit $2 offset $3`, pattern, p.Limit, p.Offset)
	if err != nil {
		fail(w, "list users", err)
		return
	}
	defer rows.Close()

	out := []userRow{}
	for rows.Next() {
		var u userRow
		var created time.Time
		var lastSignIn, lastActivity *time.Time
		if err := rows.Scan(&u.ID, &u.Email, &created, &lastSignIn, &u.Provider, &u.Confirmed,
			&u.HouseholdCount, &u.ActiveCount, &u.DisplayName, &lastActivity); err != nil {
			fail(w, "scan user", err)
			return
		}
		u.CreatedAt = created.UTC().Format(time.RFC3339)
		u.LastSignInAt = tsPtr(lastSignIn)
		u.LastActivityAt = tsPtr(lastActivity)
		out = append(out, u)
	}
	if err := rows.Err(); err != nil {
		fail(w, "iterate users", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"rows": out, "page": p.meta(total)})
}

type userMembership struct {
	MemberID      string  `json:"member_id"`
	HouseholdID   string  `json:"household_id"`
	HouseholdName string  `json:"household_name"`
	DisplayName   string  `json:"display_name"`
	Color         string  `json:"color"`
	HasAvatar     bool    `json:"has_avatar"`
	JoinedAt      string  `json:"joined_at"`
	LeftAt        *string `json:"left_at"`
	GoogleEmail   *string `json:"google_email"`
	GoogleSyncAt  *string `json:"google_last_sync_at"`
	GoogleCount   int     `json:"google_last_sync_count"`
	DraftsPending int     `json:"drafts_pending"`
	DraftsTotal   int     `json:"drafts_total"`
	TasksCreated  int     `json:"tasks_created"`
	Completions   int     `json:"completions"`
	IsCalOwner    bool    `json:"is_calendar_owner"`
}

type userDetail struct {
	User        userRow          `json:"user"`
	Memberships []userMembership `json:"memberships"`
	Invites     []inviteRow      `json:"invites"`
	Activity    []activityRow    `json:"activity"`
}

// GetUser is the person page: identity, every household they belong (or
// belonged) to with their per-household stats, invites addressed to their
// email, and a merged recent-activity feed.
func (a *API) GetUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var d userDetail

	var created time.Time
	var lastSignIn, lastActivity *time.Time
	err := a.DB.QueryRow(r.Context(), `
		select u.id::text, u.email, coalesce(u.created_at, now()), u.last_sign_in_at,
		       nullif(u.raw_app_meta_data->>'provider',''),
		       (u.confirmed_at is not null),
		       (select count(*) from members m where m.user_id = u.id),
		       (select count(*) from members m where m.user_id = u.id and m.left_at is null),
		       (select m.display_name from members m
		         where m.user_id = u.id order by m.left_at nulls first, m.created_at desc limit 1),
		       greatest(u.last_sign_in_at,
		         (select max(t.created_at) from tasks t
		            join members m on m.id = t.created_by where m.user_id = u.id),
		         (select max(dr.created_at) from drafts dr
		            join members m on m.id = dr.source_member_id where m.user_id = u.id))
		  from auth.users u where u.id::text = $1`, id).
		Scan(&d.User.ID, &d.User.Email, &created, &lastSignIn, &d.User.Provider, &d.User.Confirmed,
			&d.User.HouseholdCount, &d.User.ActiveCount, &d.User.DisplayName, &lastActivity)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "not_found", "No user with that id.")
		return
	}
	if err != nil {
		fail(w, "load user", err)
		return
	}
	d.User.CreatedAt = created.UTC().Format(time.RFC3339)
	d.User.LastSignInAt = tsPtr(lastSignIn)
	d.User.LastActivityAt = tsPtr(lastActivity)

	rows, err := a.DB.Query(r.Context(), `
		select m.id::text, h.id::text, h.name, m.display_name, m.color,
		       (m.avatar_path is not null), m.created_at, m.left_at,
		       g.email, g.last_sync_at, coalesce(g.last_sync_count, 0),
		       (select count(*) from drafts d where d.source_member_id = m.id and d.status = 'pending'),
		       (select count(*) from drafts d where d.source_member_id = m.id),
		       (select count(*) from tasks t where t.created_by = m.id),
		       (select count(*) from completions c where c.member_id = m.id)
		         + (select count(*) from recurring_completions rc where rc.member_id = m.id),
		       (h.calendar_owner_member_id = m.id)
		  from members m
		  join households h on h.id = m.household_id
		  left join google_accounts g on g.member_id = m.id
		 where m.user_id::text = $1
		 order by m.left_at nulls first, m.created_at`, id)
	if err != nil {
		fail(w, "load memberships", err)
		return
	}
	defer rows.Close()
	d.Memberships = []userMembership{}
	for rows.Next() {
		var m userMembership
		var joined time.Time
		var left, sync *time.Time
		var calOwner *bool
		if err := rows.Scan(&m.MemberID, &m.HouseholdID, &m.HouseholdName, &m.DisplayName,
			&m.Color, &m.HasAvatar, &joined, &left, &m.GoogleEmail, &sync, &m.GoogleCount,
			&m.DraftsPending, &m.DraftsTotal, &m.TasksCreated, &m.Completions, &calOwner); err != nil {
			fail(w, "scan membership", err)
			return
		}
		m.JoinedAt = joined.UTC().Format(time.RFC3339)
		m.LeftAt = tsPtr(left)
		m.GoogleSyncAt = tsPtr(sync)
		m.IsCalOwner = calOwner != nil && *calOwner
		d.Memberships = append(d.Memberships, m)
	}
	if err := rows.Err(); err != nil {
		fail(w, "iterate memberships", err)
		return
	}

	if d.User.Email != nil {
		d.Invites, err = a.invitesForEmail(r, *d.User.Email)
		if err != nil {
			fail(w, "load invites", err)
			return
		}
	} else {
		d.Invites = []inviteRow{}
	}

	d.Activity, err = a.userActivity(r, id)
	if err != nil {
		fail(w, "load activity", err)
		return
	}
	writeJSON(w, http.StatusOK, d)
}

type activityRow struct {
	At    string `json:"at"`
	Kind  string `json:"kind"`
	Title string `json:"title"`
	Where string `json:"where"`
}

// userActivity merges the handful of timestamped things a person does. It is a
// UNION rather than a real event table because evend does not keep one; that
// is honest here and cheap at this row count.
func (a *API) userActivity(r *http.Request, userID string) ([]activityRow, error) {
	rows, err := a.DB.Query(r.Context(), `
		with mine as (select m.id, m.household_id from members m where m.user_id::text = $1)
		select at, kind, title, where_name from (
		  select t.created_at as at, 'task.created' as kind, t.title, h.name as where_name
		    from tasks t join mine on mine.id = t.created_by join households h on h.id = t.household_id
		  union all
		  select d.created_at, 'draft.captured', d.title, h.name
		    from drafts d join mine on mine.id = d.source_member_id join households h on h.id = d.household_id
		  union all
		  select c.completed_at, 'task.completed', t.title, h.name
		    from completions c join mine on mine.id = c.member_id
		    join tasks t on t.id = c.task_id join households h on h.id = t.household_id
		  union all
		  select rc.completed_at, 'task.completed', t.title, h.name
		    from recurring_completions rc join mine on mine.id = rc.member_id
		    join tasks t on t.id = rc.task_id join households h on h.id = t.household_id
		  union all
		  select e.created_at, 'expense.added', e.title, h.name
		    from expenses e join mine on mine.id = e.paid_by_member_id join households h on h.id = e.household_id
		) feed
		order by at desc
		limit 40`, userID)
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
