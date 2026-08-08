package api

// The integration suites create real households, members and drafts through
// the public API. Pointing them at the live compose database has already
// leaked dozens of fixture households into production — so the DSN is only
// accepted when it names a database literally called even_test.
//
// Bring one up next to the live db (schema copied, no data):
//
//   docker exec evend-db-1 psql -U even -d even -c 'create database even_test'
//   docker exec evend-db-1 sh -c 'pg_dump -U even --schema-only even | psql -U even -d even_test'
//
//   EVEN_TESTDB=postgres://even:PW@127.0.0.1:5433/even_test?sslmode=disable \
//   EVEN_GOTRUE_JWT_SECRET=… go test ./internal/api

import (
	"net/url"
	"os"
	"strings"
	"testing"
)

func testDBURL(t *testing.T) string {
	t.Helper()
	raw := os.Getenv("EVEN_TESTDB")
	if raw == "" {
		t.Skip("EVEN_TESTDB not set")
	}
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("EVEN_TESTDB is not a URL: %v", err)
	}
	if name := strings.Trim(u.Path, "/"); name != "even_test" {
		t.Fatalf(
			"EVEN_TESTDB points at database %q — the suite writes fixtures and only runs against a database named even_test, never the live one",
			name,
		)
	}
	return raw
}
