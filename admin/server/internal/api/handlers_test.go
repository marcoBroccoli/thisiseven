package api

import (
	"context"
	"net/http"
	"strings"
	"testing"
)

// Every read endpoint is behind the session gate. This walks the list rather
// than testing one, because a route added to the wrong chi.Group is exactly the
// mistake that would not show up anywhere else.
func TestEveryEndpointRequiresASession(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()

	for _, path := range []string{
		"/api/auth/me", "/api/dashboard", "/api/users", "/api/households",
		"/api/ops", "/api/settings", "/api/notifications",
		"/api/notifications/targets", "/api/audit", "/api/health",
	} {
		res, body := h.do(http.MethodGet, path, nil)
		if res.StatusCode != http.StatusUnauthorized {
			t.Errorf("GET %s without a session = %d (%v), want 401", path, res.StatusCode, body)
		}
	}
	for _, path := range []string{"/api/settings", "/api/notifications"} {
		res, _ := h.do(http.MethodPost, path, map[string]string{})
		if res.StatusCode != http.StatusUnauthorized {
			t.Errorf("POST %s without a session = %d, want 401", path, res.StatusCode)
		}
	}
}

// An unmatched /api path must answer JSON. Falling through to the SPA's HTML
// makes a typo'd fetch fail at parse time with a message about "<".
func TestUnknownAPIRouteIsJSONNotHTML(t *testing.T) {
	h := newHarness(t)
	res, body := h.do(http.MethodGet, "/api/does-not-exist", nil)
	if res.StatusCode != http.StatusNotFound {
		t.Fatalf("status %d, want 404", res.StatusCode)
	}
	if ct := res.Header.Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Errorf("Content-Type = %q, want application/json", ct)
	}
	if code := errCode(body); code != "no_route" {
		t.Errorf("error code = %q, want no_route", code)
	}
}

func TestHealthzNeedsNoSession(t *testing.T) {
	h := newHarness(t)
	res, body := h.do(http.MethodGet, "/healthz", nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status %d", res.StatusCode)
	}
	if body["ok"] != true {
		t.Errorf("body = %v, want {ok:true}", body)
	}
}

func TestSecurityHeadersArePresent(t *testing.T) {
	h := newHarness(t)
	res, _ := h.do(http.MethodGet, "/healthz", nil)
	for header, want := range map[string]string{
		"X-Content-Type-Options": "nosniff",
		"X-Frame-Options":        "DENY",
		"Referrer-Policy":        "no-referrer",
	} {
		if got := res.Header.Get(header); got != want {
			t.Errorf("%s = %q, want %q", header, got, want)
		}
	}
	if csp := res.Header.Get("Content-Security-Policy"); csp == "" {
		t.Error("no Content-Security-Policy header")
	}
}

// ---------------------------------------------------------------- roles

func TestViewerRoleCanReadButNotWrite(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.setRole("viewer")
	h.signIn()

	if res, body := h.do(http.MethodGet, "/api/settings", nil); res.StatusCode != http.StatusOK {
		t.Fatalf("viewer GET /api/settings = %d (%v), want 200", res.StatusCode, body)
	}
	res, body := h.do(http.MethodPut, "/api/settings/some_key",
		map[string]any{"key": "some_key", "value": true, "description": nil})
	if res.StatusCode != http.StatusForbidden {
		t.Fatalf("viewer PUT = %d (%v), want 403", res.StatusCode, body)
	}
	if code := errCode(body); code != "read_only" {
		t.Errorf("error code = %q, want read_only", code)
	}
}

// ---------------------------------------------------------------- settings

func TestSettingLifecycleIsAudited(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	// create
	res, body := h.do(http.MethodPut, "/api/settings/poll_minutes",
		map[string]any{"key": "poll_minutes", "value": 30, "description": "how often"})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("create = %d (%v)", res.StatusCode, body)
	}
	// update
	if res, body = h.do(http.MethodPut, "/api/settings/poll_minutes",
		map[string]any{"key": "poll_minutes", "value": 45, "description": nil}); res.StatusCode != http.StatusOK {
		t.Fatalf("update = %d (%v)", res.StatusCode, body)
	}
	// delete
	if res, body = h.do(http.MethodDelete, "/api/settings/poll_minutes", nil); res.StatusCode != http.StatusOK {
		t.Fatalf("delete = %d (%v)", res.StatusCode, body)
	}

	rows, err := h.db.Query(context.Background(),
		`select action, target_id, actor_email, (before_json is not null), (after_json is not null)
		   from admin.audit_log order by id`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()

	type entry struct {
		action, target, actor string
		hasBefore, hasAfter   bool
	}
	var got []entry
	for rows.Next() {
		var e entry
		if err := rows.Scan(&e.action, &e.target, &e.actor, &e.hasBefore, &e.hasAfter); err != nil {
			t.Fatal(err)
		}
		got = append(got, e)
	}
	if len(got) != 3 {
		t.Fatalf("audit_log has %d rows, want 3 (create, update, delete)", len(got))
	}
	want := []string{"setting.create", "setting.update", "setting.delete"}
	for i, w := range want {
		if got[i].action != w {
			t.Errorf("audit row %d action = %q, want %q", i, got[i].action, w)
		}
		if got[i].actor != testAdminEmail {
			t.Errorf("audit row %d actor = %q, want %q", i, got[i].actor, testAdminEmail)
		}
		if got[i].target != "poll_minutes" {
			t.Errorf("audit row %d target = %q, want poll_minutes", i, got[i].target)
		}
	}
	// The create has no before; the update and delete both carry one, which is
	// what makes the log reversible by hand.
	if got[0].hasBefore {
		t.Error("create recorded a before state")
	}
	if !got[1].hasBefore || !got[1].hasAfter {
		t.Error("update should record both before and after")
	}
	if !got[2].hasBefore {
		t.Error("delete should record what was removed")
	}
}

func TestSettingRejectsABadKeyAndBadJSON(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	res, body := h.do(http.MethodPost, "/api/settings",
		map[string]any{"key": "Bad Key!", "value": 1, "description": nil})
	if res.StatusCode != http.StatusBadRequest {
		t.Errorf("bad key = %d (%v), want 400", res.StatusCode, body)
	}
	if code := errCode(body); code != "bad_key" {
		t.Errorf("error code = %q, want bad_key", code)
	}
}

func TestDeletingAMissingSettingIs404(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	res, body := h.do(http.MethodDelete, "/api/settings/never_existed", nil)
	if res.StatusCode != http.StatusNotFound {
		t.Errorf("status %d (%v), want 404", res.StatusCode, body)
	}
}

// ---------------------------------------------------------------- outbox

func TestQueueNotificationToEveryoneThenCancel(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()
	if !h.productTablesPresent() {
		t.Skip("even_test has no product schema — audience counting needs members")
	}

	res, body := h.do(http.MethodPost, "/api/notifications", map[string]any{
		"audience": "all",
		"title":    "Weekly settle-up",
		"body":     "Sunday is close to done.",
	})
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("queue = %d (%v), want 201", res.StatusCode, body)
	}
	id, _ := body["id"].(string)
	if id == "" {
		t.Fatal("no id returned")
	}

	// Nothing is delivered — the row must be 'queued', never 'sent'.
	var status string
	if err := h.db.QueryRow(context.Background(),
		`select status from admin.notification_outbox where id::text = $1`, id).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != "queued" {
		t.Fatalf("status = %q, want queued", status)
	}

	if res, body = h.do(http.MethodPost, "/api/notifications/"+id+"/cancel", nil); res.StatusCode != http.StatusOK {
		t.Fatalf("cancel = %d (%v)", res.StatusCode, body)
	}
	if err := h.db.QueryRow(context.Background(),
		`select status from admin.notification_outbox where id::text = $1`, id).Scan(&status); err != nil {
		t.Fatal(err)
	}
	if status != "cancelled" {
		t.Errorf("status after cancel = %q, want cancelled", status)
	}

	// Cancelling twice is a conflict, not a silent success.
	if res, _ = h.do(http.MethodPost, "/api/notifications/"+id+"/cancel", nil); res.StatusCode != http.StatusConflict {
		t.Errorf("second cancel = %d, want 409", res.StatusCode)
	}
}

func TestQueueNotificationValidatesItsInput(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	cases := []struct {
		name string
		body map[string]any
		want string
	}{
		{"no title", map[string]any{"audience": "all", "title": "", "body": "x"}, "bad_title"},
		{"no body", map[string]any{"audience": "all", "title": "x", "body": ""}, "bad_body"},
		{"bad audience", map[string]any{"audience": "nobody", "title": "x", "body": "y"}, "bad_audience"},
		{"household without id", map[string]any{"audience": "household", "title": "x", "body": "y"}, "missing_target"},
		{"user without id", map[string]any{"audience": "user", "title": "x", "body": "y"}, "missing_target"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			res, body := h.do(http.MethodPost, "/api/notifications", c.body)
			if res.StatusCode != http.StatusBadRequest {
				t.Fatalf("status %d (%v), want 400", res.StatusCode, body)
			}
			if code := errCode(body); code != c.want {
				t.Errorf("error code = %q, want %q", code, c.want)
			}
		})
	}
}

func TestQueueNotificationRejectsAnUnknownHousehold(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()
	if !h.productTablesPresent() {
		t.Skip("even_test has no product schema")
	}
	res, body := h.do(http.MethodPost, "/api/notifications", map[string]any{
		"audience":     "household",
		"household_id": "00000000-0000-0000-0000-000000000000",
		"title":        "x",
		"body":         "y",
	})
	if res.StatusCode != http.StatusNotFound {
		t.Errorf("status %d (%v), want 404", res.StatusCode, body)
	}
}

// ---------------------------------------------------------------- reads

func TestReadPagesRespond(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	// /api/health and /api/audit need only the admin schema.
	res, body := h.do(http.MethodGet, "/api/health", nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("health = %d (%v)", res.StatusCode, body)
	}
	deps, _ := body["dependencies"].([]any)
	if len(deps) < 2 {
		t.Errorf("health reported %d dependencies, want postgres and evend", len(deps))
	}
	// evend is deliberately pointed at a dead port; health must say so rather
	// than fail the request.
	for _, d := range deps {
		dep, _ := d.(map[string]any)
		if dep["name"] == "postgres" && dep["ok"] != true {
			t.Error("postgres reported down while the suite is talking to it")
		}
		if dep["name"] == "evend" && dep["ok"] != false {
			t.Error("a dead evend should be reported down")
		}
	}

	if res, body = h.do(http.MethodGet, "/api/audit", nil); res.StatusCode != http.StatusOK {
		t.Fatalf("audit = %d (%v)", res.StatusCode, body)
	}
	if _, ok := body["rows"].([]any); !ok {
		t.Errorf("audit did not return a rows array: %v", body)
	}

	if !h.productTablesPresent() {
		t.Skip("even_test has no product schema — the rest of the pages need it")
	}
	// /api/notifications is in this list because it LEFT JOINs households and
	// auth.users to name its targets. It was once selecting those columns
	// without joining the tables, which only showed up as a 500 in a browser.
	for _, path := range []string{"/api/dashboard", "/api/users", "/api/households", "/api/ops",
		"/api/notifications", "/api/notifications/targets"} {
		if res, body = h.do(http.MethodGet, path, nil); res.StatusCode != http.StatusOK {
			t.Errorf("GET %s = %d (%v), want 200", path, res.StatusCode, body)
		}
		if _, ok := body["rows"].([]any); !ok && path != "/api/notifications/targets" &&
			path != "/api/dashboard" && path != "/api/ops" {
			t.Errorf("GET %s did not return a rows array", path)
		}
	}
}

func TestPaginationMetaIsSane(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()
	if !h.productTablesPresent() {
		t.Skip("even_test has no product schema")
	}
	res, body := h.do(http.MethodGet, "/api/users?per_page=5&page=1", nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status %d", res.StatusCode)
	}
	meta, ok := body["page"].(map[string]any)
	if !ok {
		t.Fatalf("no page meta in %v", body)
	}
	if meta["per_page"] != float64(5) {
		t.Errorf("per_page = %v, want 5", meta["per_page"])
	}
	if meta["page"] != float64(1) {
		t.Errorf("page = %v, want 1", meta["page"])
	}
	if tp, _ := meta["total_pages"].(float64); tp < 1 {
		t.Errorf("total_pages = %v, want at least 1 even when empty", meta["total_pages"])
	}
}

// per_page is capped server-side: the console is for looking, not for pulling
// the whole database through one request.
func TestPerPageIsCapped(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()
	if !h.productTablesPresent() {
		t.Skip("even_test has no product schema")
	}
	res, body := h.do(http.MethodGet, "/api/users?per_page=100000", nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status %d", res.StatusCode)
	}
	meta, _ := body["page"].(map[string]any)
	if meta["per_page"] != float64(200) {
		t.Errorf("per_page = %v, want it capped at 200", meta["per_page"])
	}
}

func TestMissingHouseholdAndUserAre404(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()
	if !h.productTablesPresent() {
		t.Skip("even_test has no product schema")
	}
	const nilUUID = "00000000-0000-0000-0000-000000000000"
	for _, path := range []string{"/api/households/" + nilUUID, "/api/users/" + nilUUID} {
		if res, body := h.do(http.MethodGet, path, nil); res.StatusCode != http.StatusNotFound {
			t.Errorf("GET %s = %d (%v), want 404", path, res.StatusCode, body)
		}
	}
}
