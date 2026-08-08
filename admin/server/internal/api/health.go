package api

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"sort"
	"time"
)

type dependency struct {
	Name      string `json:"name"`
	OK        bool   `json:"ok"`
	Detail    string `json:"detail"`
	LatencyMS int64  `json:"latency_ms"`
}

type tableCount struct {
	Schema string `json:"schema"`
	Table  string `json:"table"`
	Rows   int64  `json:"rows"`
}

type healthResponse struct {
	Dependencies []dependency   `json:"dependencies"`
	Pool         map[string]any `json:"pool"`
	Database     map[string]any `json:"database"`
	Tables       []tableCount   `json:"tables"`
	Migrations   []string       `json:"admin_migrations"`
	Logins       map[string]int `json:"logins_24h"`
	CheckedAt    string         `json:"checked_at"`
}

// Health is the "is anything on fire" page. Row counts are exact counts, not
// planner estimates: at Even's size the difference is milliseconds, and an
// estimate that says 0 for a freshly-populated table is worse than useless.
func (a *API) Health(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	resp := healthResponse{
		Pool:      map[string]any{},
		Database:  map[string]any{},
		Logins:    map[string]int{},
		CheckedAt: a.now().UTC().Format(time.RFC3339),
	}

	// --- postgres ---------------------------------------------------------
	dbStart := time.Now()
	var pgVersion string
	dbErr := a.DB.QueryRow(ctx, `select version()`).Scan(&pgVersion)
	resp.Dependencies = append(resp.Dependencies, dependency{
		Name: "postgres", OK: dbErr == nil,
		Detail:    firstNonEmpty(pgVersion, errText(dbErr)),
		LatencyMS: time.Since(dbStart).Milliseconds(),
	})

	// --- evend ------------------------------------------------------------
	evStart := time.Now()
	evOK, evDetail := a.probeEvend(ctx)
	resp.Dependencies = append(resp.Dependencies, dependency{
		Name: "evend", OK: evOK, Detail: evDetail,
		LatencyMS: time.Since(evStart).Milliseconds(),
	})

	stat := a.DB.Stat()
	resp.Pool = map[string]any{
		"total_conns":        stat.TotalConns(),
		"acquired_conns":     stat.AcquiredConns(),
		"idle_conns":         stat.IdleConns(),
		"max_conns":          stat.MaxConns(),
		"acquire_count":      stat.AcquireCount(),
		"canceled_acquires":  stat.CanceledAcquireCount(),
		"empty_acquire_wait": stat.EmptyAcquireCount(),
	}

	var dbName, dbSize string
	var backends int
	if err := a.DB.QueryRow(ctx, `
		select current_database(),
		       pg_size_pretty(pg_database_size(current_database())),
		       (select count(*) from pg_stat_activity where datname = current_database())`).
		Scan(&dbName, &dbSize, &backends); err == nil {
		resp.Database = map[string]any{"name": dbName, "size": dbSize, "backends": backends}
	}

	// --- row counts -------------------------------------------------------
	// The set is hand-written: it is the product's story plus the console's own
	// tables, in the order an operator wants to read them.
	targets := []tableCount{
		{"auth", "users", 0},
		{"public", "households", 0},
		{"public", "members", 0},
		{"public", "weeks", 0},
		{"public", "tasks", 0},
		{"public", "completions", 0},
		{"public", "recurring_completions", 0},
		{"public", "drafts", 0},
		{"public", "processed_emails", 0},
		{"public", "google_accounts", 0},
		{"public", "household_invites", 0},
		{"public", "expenses", 0},
		{"public", "settlements", 0},
		{"public", "appreciations", 0},
		{"public", "trades", 0},
		{"admin", "admin_users", 0},
		{"admin", "sessions", 0},
		{"admin", "audit_log", 0},
		{"admin", "settings", 0},
		{"admin", "notification_outbox", 0},
	}
	resp.Tables = []tableCount{}
	for _, t := range targets {
		var n int64
		// Identifiers are constants above, never request input.
		if err := a.DB.QueryRow(ctx, `select count(*) from `+t.Schema+`.`+t.Table).Scan(&n); err != nil {
			continue // a table this build does not know about is skipped, not fatal
		}
		t.Rows = n
		resp.Tables = append(resp.Tables, t)
	}

	mig, err := a.distinct(ctx, `select name from admin.schema_migrations order by name`)
	if err == nil {
		sort.Strings(mig)
		resp.Migrations = mig
	} else {
		resp.Migrations = []string{}
	}

	var ok, failed int
	if err := a.DB.QueryRow(ctx, `
		select count(*) filter (where ok), count(*) filter (where not ok)
		  from admin.login_attempts where created_at > now() - interval '24 hours'`).
		Scan(&ok, &failed); err == nil {
		resp.Logins["ok"] = ok
		resp.Logins["failed"] = failed
	}

	writeJSON(w, http.StatusOK, resp)
}

func (a *API) probeEvend(ctx context.Context) (bool, string) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, a.EvendBaseURL+"/healthz", nil)
	if err != nil {
		return false, err.Error()
	}
	res, err := a.httpClient().Do(req)
	if err != nil {
		return false, "unreachable at " + a.EvendBaseURL + ": " + err.Error()
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	if res.StatusCode != http.StatusOK {
		return false, res.Status + " from " + a.EvendBaseURL + "/healthz"
	}
	var payload map[string]any
	if json.Unmarshal(body, &payload) == nil {
		if ok, _ := payload["ok"].(bool); ok {
			return true, a.EvendBaseURL + "/healthz → ok"
		}
	}
	return false, "unexpected body from " + a.EvendBaseURL + "/healthz"
}

func errText(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
