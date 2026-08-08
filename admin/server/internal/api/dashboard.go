package api

import (
	"context"
	"fmt"
	"net/http"
	"time"
)

type statTile struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Value int    `json:"value"`
	// Sub is the secondary line ("3 in the last 7 days"); empty hides it.
	Sub string `json:"sub,omitempty"`
}

type trendSeries struct {
	Key    string `json:"key"`
	Label  string `json:"label"`
	Points []int  `json:"points"`
}

type dashboardResponse struct {
	Tiles    []statTile    `json:"tiles"`
	Days     []string      `json:"days"`
	Series   []trendSeries `json:"series"`
	Attention []attentionRow `json:"attention"`
	GeneratedAt string      `json:"generated_at"`
}

type attentionRow struct {
	Kind        string `json:"kind"`
	Label       string `json:"label"`
	Count       int    `json:"count"`
	Href        string `json:"href"`
	Severity    string `json:"severity"` // "warn" | "info"
}

const trendDays = 14

// Dashboard is one round trip: every tile and the whole 14-day trend. The
// queries are counts over indexed columns on tables this size, so a single
// handler is cheaper than fourteen chatty ones.
func (a *API) Dashboard(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	resp := dashboardResponse{GeneratedAt: a.now().UTC().Format(time.RFC3339)}

	// --- totals -----------------------------------------------------------
	type tileSpec struct {
		key, label, query, subQuery, subFmt string
	}
	specs := []tileSpec{
		{"users", "Signed-up users",
			`select count(*) from auth.users`,
			`select count(*) from auth.users where created_at > now() - interval '7 days'`,
			"+%d this week"},
		{"households", "Households",
			`select count(*) from households`,
			`select count(*) from households where created_at > now() - interval '7 days'`,
			"+%d this week"},
		{"members", "Active members",
			`select count(*) from members where left_at is null`,
			`select count(*) from members where left_at is not null`,
			"%d departed"},
		{"tasks_open", "Open tasks",
			`select count(*) from tasks where archived_at is null`,
			`select count(*) from tasks where archived_at is null and recurrence <> 'none'`,
			"%d recurring"},
		{"completions", "Completions (7d)",
			`select (select count(*) from completions where completed_at > now() - interval '7 days')
			      + (select count(*) from recurring_completions where completed_at > now() - interval '7 days')`,
			`select count(*) from weeks where closed_at is null`,
			"%d open weeks"},
		{"drafts_pending", "Drafts pending",
			`select count(*) from drafts where status = 'pending'`,
			`select count(*) from drafts where status = 'approved'`,
			"%d approved all-time"},
		{"google", "Google connections",
			`select count(*) from google_accounts`,
			`select count(distinct household_id) from google_accounts`,
			"across %d households"},
		{"invites", "Pending invites",
			`select count(*) from household_invites where status = 'pending'`,
			`select count(*) from household_invites where status = 'accepted'`,
			"%d accepted"},
	}
	for _, s := range specs {
		var value, sub int
		if err := a.DB.QueryRow(ctx, s.query).Scan(&value); err != nil {
			fail(w, "dashboard tile "+s.key, err)
			return
		}
		if err := a.DB.QueryRow(ctx, s.subQuery).Scan(&sub); err != nil {
			fail(w, "dashboard sub "+s.key, err)
			return
		}
		resp.Tiles = append(resp.Tiles, statTile{
			Key: s.key, Label: s.label, Value: value, Sub: sprintfCount(s.subFmt, sub),
		})
	}

	// --- 14-day trend -----------------------------------------------------
	// One generate_series spine per series so a day with no rows is a 0, not a
	// gap the chart would silently close.
	resp.Days = lastDays(a.now(), trendDays)
	series := []struct {
		key, label, table, column, extra string
	}{
		{"users", "New users", "auth.users", "created_at", ""},
		{"households", "New households", "households", "created_at", ""},
		{"tasks", "Tasks created", "tasks", "created_at", ""},
		{"drafts", "Drafts captured", "drafts", "created_at", ""},
	}
	for _, s := range series {
		pts, err := a.dailyCounts(ctx, s.table, s.column, s.extra)
		if err != nil {
			fail(w, "trend "+s.key, err)
			return
		}
		resp.Series = append(resp.Series, trendSeries{Key: s.key, Label: s.label, Points: pts})
	}
	// Completions live in two tables since 008; the chart shows the sum.
	c1, err := a.dailyCounts(ctx, "completions", "completed_at", "")
	if err != nil {
		fail(w, "trend completions", err)
		return
	}
	c2, err := a.dailyCounts(ctx, "recurring_completions", "completed_at", "")
	if err != nil {
		fail(w, "trend recurring completions", err)
		return
	}
	sum := make([]int, len(c1))
	for i := range c1 {
		sum[i] = c1[i] + c2[i]
	}
	resp.Series = append(resp.Series, trendSeries{Key: "completions", Label: "Completions", Points: sum})

	// --- needs attention --------------------------------------------------
	attention := []struct {
		kind, label, query, href, severity string
	}{
		{"calendar_retry", "Tasks stuck in calendar retry",
			`select count(*) from tasks where calendar_sync_state = 'retry_required' and archived_at is null`,
			"/ops", "warn"},
		{"calendar_deleted", "Todos deleted in Google, not resolved",
			`select count(*) from tasks where calendar_sync_state = 'external_deleted' and archived_at is null`,
			"/ops", "warn"},
		{"stale_gmail", "Mailboxes not synced in 24h",
			`select count(*) from google_accounts where last_sync_at is null or last_sync_at < now() - interval '24 hours'`,
			"/ops", "info"},
		{"empty_households", "Households with no active member",
			`select count(*) from households h where not exists (
			   select 1 from members m where m.household_id = h.id and m.left_at is null)`,
			"/households", "info"},
		{"login_failures", "Failed admin logins (24h)",
			`select count(*) from admin.login_attempts where ok = false and created_at > now() - interval '24 hours'`,
			"/health", "info"},
	}
	resp.Attention = []attentionRow{}
	for _, at := range attention {
		var n int
		if err := a.DB.QueryRow(ctx, at.query).Scan(&n); err != nil {
			fail(w, "attention "+at.kind, err)
			return
		}
		resp.Attention = append(resp.Attention, attentionRow{
			Kind: at.kind, Label: at.label, Count: n, Href: at.href, Severity: at.severity,
		})
	}

	writeJSON(w, http.StatusOK, resp)
}

// dailyCounts returns exactly trendDays numbers, oldest first. The table and
// column names are compile-time constants from the caller above — never
// request input — so the interpolation is safe.
func (a *API) dailyCounts(ctx context.Context, table, column, extra string) ([]int, error) {
	q := `
		with spine as (
		  select generate_series(
		    (current_date - ($1::int - 1))::date, current_date, interval '1 day')::date as day
		)
		select spine.day, count(t.*)
		  from spine
		  left join ` + table + ` t
		    on t.` + column + `::date = spine.day ` + extra + `
		 group by spine.day
		 order by spine.day`
	rows, err := a.DB.Query(ctx, q, trendDays)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]int, 0, trendDays)
	for rows.Next() {
		var day time.Time
		var n int
		if err := rows.Scan(&day, &n); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

func lastDays(now time.Time, n int) []string {
	out := make([]string, 0, n)
	for i := n - 1; i >= 0; i-- {
		out = append(out, now.AddDate(0, 0, -i).Format("2006-01-02"))
	}
	return out
}

func sprintfCount(format string, n int) string {
	if format == "" {
		return ""
	}
	return fmt.Sprintf(format, n)
}
