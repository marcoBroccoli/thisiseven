package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
)

func TestCalendarSyncImportsAndSurfacesExternalChanges(t *testing.T) {
	dbURL := os.Getenv("EVEN_TESTDB")
	if dbURL == "" {
		t.Skip("EVEN_TESTDB not set")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 3600})
	})
	mux.HandleFunc("/calendar/v3/calendars/even-cal/events", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("showDeleted") != "true" {
			t.Errorf("expected deleted events in reconciliation query: %s", r.URL.RawQuery)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"items": []map[string]any{
			{
				"id": "changed-event", "summary": "Book the plumber", "status": "confirmed",
				"htmlLink": "https://calendar.google.com/changed",
				"start":    map[string]string{"date": "2026-08-08"},
			},
			{"id": "deleted-event", "status": "cancelled"},
			{
				"id": "direct-event", "summary": "Wash the dog", "status": "confirmed",
				"htmlLink": "https://calendar.google.com/direct",
				"start":    map[string]string{"dateTime": "2026-08-09T10:00:00+02:00"},
			},
			{
				"id": "repeat-instance", "recurringEventId": "repeat-master", "summary": "Wash the dog", "status": "confirmed",
				"start": map[string]string{"date": "2026-08-15"},
			},
		}})
	})
	fake := httptest.NewServer(mux)
	defer fake.Close()

	a := &API{DB: pool, Google: google.New("cid", "secret", "", fake.URL, fake.URL)}
	hh, member, week := seedCalHousehold(t, pool, "Calendar Reconciliation")
	if _, err := pool.Exec(ctx, `
		insert into google_accounts (household_id, email, refresh_token, client_kind, connected_by, calendar_id)
		values ($1, 'house@example.com', 'refresh', 'desktop', $2, 'even-cal')`, hh, member); err != nil {
		t.Fatal(err)
	}
	var changedID, deletedID, recurringID string
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on,
			google_event_id, calendar_sync_state)
		values ($1, 'Call plumber', 'admin', $2, 1, 'none', '2026-08-07', 'changed-event', 'synced')
		returning id`, hh, member).Scan(&changedID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on,
			google_event_id, calendar_sync_state)
		values ($1, 'Old calendar task', 'admin', $2, 1, 'none', '2026-08-10', 'deleted-event', 'synced')
		returning id`, hh, member).Scan(&deletedID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on,
			google_event_id, calendar_sync_state)
		values ($1, 'Wash the dog', 'chore', $2, 1, 'weekly', '2026-08-08', 'repeat-master', 'synced')
		returning id`, hh, member).Scan(&recurringID); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: member, HouseholdID: hh, Household: "Calendar Reconciliation", WeekID: week}
	out, err := a.syncCalendar(ctx, m)
	if err != nil {
		t.Fatal(err)
	}
	if out.Updated != 1 || out.Deleted != 1 || out.Imported != 1 {
		t.Fatalf("unexpected reconciliation: %+v", out)
	}

	var title, due, state string
	if err := pool.QueryRow(ctx, `select title, due_on::text, calendar_sync_state from tasks where id = $1`, changedID).
		Scan(&title, &due, &state); err != nil {
		t.Fatal(err)
	}
	if title != "Book the plumber" || due != "2026-08-08" || state != "external_changed" {
		t.Fatalf("external edit not surfaced: %q %q %q", title, due, state)
	}
	if err := pool.QueryRow(ctx, `select calendar_sync_state from tasks where id = $1`, deletedID).Scan(&state); err != nil {
		t.Fatal(err)
	}
	if state != "external_deleted" {
		t.Fatalf("external deletion state = %q", state)
	}
	var directTitle, origin, directState string
	if err := pool.QueryRow(ctx, `
		select title, origin_label, calendar_sync_state from tasks
		where household_id = $1 and google_event_id = 'direct-event'`, hh).
		Scan(&directTitle, &origin, &directState); err != nil {
		t.Fatal(err)
	}
	if directTitle != "Wash the dog" || origin != "CALENDAR · IMPORTED" || directState != "synced" {
		t.Fatalf("direct event import = %q %q %q", directTitle, origin, directState)
	}
	var recurringCount int
	if err := pool.QueryRow(ctx, `select count(*) from tasks where household_id = $1 and google_event_id = 'repeat-instance'`, hh).
		Scan(&recurringCount); err != nil || recurringCount != 0 {
		t.Fatalf("recurring instance must not import a duplicate: count=%d err=%v", recurringCount, err)
	}
	if err := pool.QueryRow(ctx, `select calendar_sync_state from tasks where id = $1`, recurringID).Scan(&state); err != nil || state != "synced" {
		t.Fatalf("recurring master state = %q, %v", state, err)
	}
	var syncedAt *time.Time
	if err := pool.QueryRow(ctx, `select calendar_last_sync_at from google_accounts where household_id = $1`, hh).Scan(&syncedAt); err != nil || syncedAt == nil {
		t.Fatalf("calendar sync timestamp = %v, %v", syncedAt, err)
	}
}
