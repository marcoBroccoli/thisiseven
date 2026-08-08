package api

// The handler suite writes real rows: admin users, sessions, audit entries,
// queued notifications. Evend's own suite has already leaked fixtures into
// production once by being pointed at the compose database, so the same guard
// applies here — the DSN is only accepted when it names a database literally
// called even_test.
//
// Bring one up next to the live db (schema copied, no data):
//
//	docker exec evend-db-1 psql -U even -d even -c 'create database even_test'
//	docker exec evend-db-1 sh -c 'pg_dump -U even --schema-only even | psql -U even -d even_test'
//
//	ADMIN_TESTDB=postgres://even:PW@127.0.0.1:5433/even_test?sslmode=disable \
//	  go test ./internal/api
//
// Without ADMIN_TESTDB the suite skips, so `go test ./...` stays green on a
// machine with no database.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/marcoBroccoli/thisiseven/admin/internal/adminauth"
	"github.com/marcoBroccoli/thisiseven/admin/internal/store"
)

func testDBURL(t *testing.T) string {
	t.Helper()
	raw := os.Getenv("ADMIN_TESTDB")
	if raw == "" {
		t.Skip("ADMIN_TESTDB not set")
	}
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("ADMIN_TESTDB is not a URL: %v", err)
	}
	if name := strings.Trim(u.Path, "/"); name != "even_test" {
		t.Fatalf(
			"ADMIN_TESTDB points at database %q — this suite writes fixtures and only runs against a database named even_test, never the live one",
			name,
		)
	}
	return raw
}

// harness is one isolated console: a fresh pool, migrated admin schema, empty
// admin tables, and an http client that keeps cookies the way a browser does.
type harness struct {
	t      *testing.T
	api    *API
	server *httptest.Server
	client *http.Client
	db     store.DB
}

const (
	testAdminEmail    = "ops@even.test"
	testAdminPassword = "console-password-9!"
)

func newHarness(t *testing.T) *harness {
	t.Helper()
	ctx := context.Background()

	db, err := store.Open(ctx, testDBURL(t))
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	if err := store.WaitReady(ctx, db, 10*time.Second); err != nil {
		t.Fatalf("test database unreachable: %v", err)
	}
	if err := store.Migrate(ctx, db); err != nil {
		t.Fatalf("migrate admin schema: %v", err)
	}
	// Every test starts from an empty console. The product tables are left
	// exactly as they are — this suite never writes to them.
	if _, err := db.Exec(ctx, `truncate admin.admin_users, admin.sessions,
		admin.login_challenges, admin.login_attempts, admin.audit_log,
		admin.notification_outbox restart identity cascade`); err != nil {
		t.Fatalf("reset admin tables: %v", err)
	}

	api := &API{
		DB:           db,
		SessionTTL:   12 * time.Hour,
		CookieSecure: false, // httptest speaks plain http
		TOTPIssuer:   "Even Admin Test",
		EvendBaseURL: "http://127.0.0.1:1", // deliberately dead: health must report it down, not hang
		HTTP:         &http.Client{Timeout: 200 * time.Millisecond},
	}
	server := httptest.NewServer(Router(api, http.NotFoundHandler()))
	jar, err := cookiejar.New(nil)
	if err != nil {
		t.Fatalf("cookie jar: %v", err)
	}

	h := &harness{
		t:      t,
		api:    api,
		server: server,
		client: &http.Client{Jar: jar, Timeout: 10 * time.Second},
		db:     db,
	}
	t.Cleanup(func() {
		server.Close()
		db.Close()
	})
	return h
}

// seedAdmin creates the bootstrap account. Bootstrap refuses to run when any
// admin exists, which is exactly the behaviour one of the tests asserts.
func (h *harness) seedAdmin() {
	h.t.Helper()
	if err := store.Bootstrap(context.Background(), h.db, testAdminEmail, testAdminPassword); err != nil {
		h.t.Fatalf("seed admin: %v", err)
	}
}

func (h *harness) setRole(role string) {
	h.t.Helper()
	if _, err := h.db.Exec(context.Background(),
		`update admin.admin_users set role = $1 where email = $2`, role, testAdminEmail); err != nil {
		h.t.Fatalf("set role: %v", err)
	}
}

// do issues a request against the harness server. body may be nil.
func (h *harness) do(method, path string, body any) (*http.Response, map[string]any) {
	h.t.Helper()
	var reader *strings.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			h.t.Fatalf("marshal request: %v", err)
		}
		reader = strings.NewReader(string(raw))
	} else {
		reader = strings.NewReader("")
	}
	req, err := http.NewRequest(method, h.server.URL+path, reader)
	if err != nil {
		h.t.Fatalf("build request: %v", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := h.client.Do(req)
	if err != nil {
		h.t.Fatalf("%s %s: %v", method, path, err)
	}
	defer res.Body.Close()

	decoded := map[string]any{}
	if err := json.NewDecoder(res.Body).Decode(&decoded); err != nil {
		// A 204 or an empty body is not a failure; the caller checks status.
		decoded = map[string]any{}
	}
	return res, decoded
}

// signIn walks the whole two-step flow and leaves a live session in the jar.
func (h *harness) signIn() {
	h.t.Helper()
	res, body := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": testAdminEmail, "password": testAdminPassword})
	if res.StatusCode != http.StatusOK {
		h.t.Fatalf("login: status %d, body %v", res.StatusCode, body)
	}

	secret, _ := body["secret"].(string)
	if secret == "" {
		// Already enrolled — read the stored secret so the test can compute a
		// valid code. Only a test may do this; the API never returns it again.
		if err := h.db.QueryRow(context.Background(),
			`select totp_secret from admin.admin_users where email = $1`,
			testAdminEmail).Scan(&secret); err != nil {
			h.t.Fatalf("read totp secret: %v", err)
		}
	}
	code, err := adminauth.TOTPCode(secret, time.Now())
	if err != nil {
		h.t.Fatalf("compute totp: %v", err)
	}
	res, body = h.do(http.MethodPost, "/api/auth/totp", map[string]string{"code": code})
	if res.StatusCode != http.StatusOK {
		h.t.Fatalf("totp: status %d, body %v", res.StatusCode, body)
	}
}

// productTablesPresent reports whether even_test carries evend's schema. A bare
// even_test (admin schema only) still exercises auth, settings, notifications
// and the audit log; the pages that read product tables skip instead of failing
// on a database that was never populated.
func (h *harness) productTablesPresent() bool {
	h.t.Helper()
	var ok bool
	if err := h.db.QueryRow(context.Background(),
		`select exists (select 1 from information_schema.tables
		  where table_schema = 'public' and table_name = 'households')`).Scan(&ok); err != nil {
		return false
	}
	return ok
}

func errCode(body map[string]any) string {
	env, ok := body["error"].(map[string]any)
	if !ok {
		return ""
	}
	code, _ := env["code"].(string)
	return code
}
