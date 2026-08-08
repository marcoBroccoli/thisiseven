package api

// Optional time of day on a todo. Runs only with EVEN_TESTDB (compose db),
// like TestFullFlow.
//
// The contract: with a time, the shared Calendar event is a real one-hour slot
// at that local hour; without one, everything stays the all-day event Even has
// always written. The two shapes must never mix in one payload — Google 400s a
// start carrying both a date and a dateTime.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
)

// calendarSpy is the fake Google the publish path talks to: it records every
// event payload Even sends, which is the only honest way to assert "this todo
// became a timed slot".
type calendarSpy struct {
	mu       sync.Mutex
	inserts  []google.EventPayload
	updates  []google.EventPayload
	eventID  string
	htmlLink string
}

func newCalendarSpy(t *testing.T) (*calendarSpy, *httptest.Server) {
	t.Helper()
	spy := &calendarSpy{eventID: "timed-event", htmlLink: "https://calendar.google.com/timed"}
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 3600})
	})
	decode := func(r *http.Request) google.EventPayload {
		var payload google.EventPayload
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Errorf("calendar payload: %v", err)
		}
		return payload
	}
	mux.HandleFunc("POST /calendar/v3/calendars/even-cal/events", func(w http.ResponseWriter, r *http.Request) {
		payload := decode(r)
		spy.mu.Lock()
		spy.inserts = append(spy.inserts, payload)
		spy.mu.Unlock()
		_ = json.NewEncoder(w).Encode(map[string]any{"id": spy.eventID, "htmlLink": spy.htmlLink})
	})
	mux.HandleFunc("PUT /calendar/v3/calendars/even-cal/events/{id}", func(w http.ResponseWriter, r *http.Request) {
		payload := decode(r)
		spy.mu.Lock()
		spy.updates = append(spy.updates, payload)
		spy.mu.Unlock()
		_ = json.NewEncoder(w).Encode(map[string]any{"id": r.PathValue("id"), "htmlLink": spy.htmlLink})
	})
	mux.HandleFunc("DELETE /calendar/v3/calendars/even-cal/events/{id}", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return spy, srv
}

func (s *calendarSpy) lastInsert(t *testing.T) google.EventPayload {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.inserts) == 0 {
		t.Fatal("no calendar event was inserted")
	}
	return s.inserts[len(s.inserts)-1]
}

func (s *calendarSpy) lastUpdate(t *testing.T) google.EventPayload {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.updates) == 0 {
		t.Fatal("no calendar event was updated")
	}
	return s.updates[len(s.updates)-1]
}

// connectCalendar gives the household a connected member who owns 'even-cal',
// which is what makes the publish path write instead of quietly skipping.
func connectCalendar(t *testing.T, pool *pgxpool.Pool, hh, member string) {
	t.Helper()
	ctx := context.Background()
	if _, err := pool.Exec(ctx, `
		insert into google_accounts (household_id, member_id, email, refresh_token, client_kind, connected_by)
		values ($1, $2, 'house@example.com', 'refresh', 'desktop', $2)`, hh, member); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
		update households set calendar_id = 'even-cal', calendar_owner_member_id = $2
		where id = $1`, hh, member); err != nil {
		t.Fatal(err)
	}
}

func TestTaskDueTimePublishesTimedCalendarSlot(t *testing.T) {
	dbURL := testDBURL(t)
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	spy, srv := newCalendarSpy(t)
	a := &API{DB: pool, Google: google.New("cid", "secret", "", srv.URL, srv.URL)}
	hh, member, week := seedCalHousehold(t, pool, "Timed Todos")
	connectCalendar(t, pool, hh, member)
	m := &Membership{MemberID: member, HouseholdID: hh, Household: "Timed Todos", WeekID: week}

	create := func(body string) *httptest.ResponseRecorder {
		t.Helper()
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/v1/tasks", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		a.CreateTask(rec, req.WithContext(context.WithValue(req.Context(), memberKey{}, m)))
		return rec
	}
	patch := func(id, body string) *httptest.ResponseRecorder {
		t.Helper()
		rec := httptest.NewRecorder()
		a.UpdateTask(rec, taskRequest(m, http.MethodPatch, "/v1/tasks/"+id, id, body))
		return rec
	}
	decodeTask := func(rec *httptest.ResponseRecorder) TaskJSON {
		t.Helper()
		var out TaskJSON
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			t.Fatalf("task body %q: %v", rec.Body.String(), err)
		}
		return out
	}
	storedTime := func(id string) *string {
		t.Helper()
		var stored *string
		if err := pool.QueryRow(ctx, `select to_char(due_time, 'HH24:MI') from tasks where id = $1`, id).
			Scan(&stored); err != nil {
			t.Fatal(err)
		}
		return stored
	}

	// --- create with a time → a one-hour slot -----------------------------
	rec := create(`{"title":"Dentist","section":"admin","owner_member_id":"` + member +
		`","weight":1,"recurrence":"none","due_on":"2026-08-19","due_time":"09:30"}`)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create timed todo: status %d — %s", rec.Code, rec.Body.String())
	}
	task := decodeTask(rec)
	if task.DueTime == nil || *task.DueTime != "09:30" {
		t.Fatalf("created due_time = %v", task.DueTime)
	}
	if stored := storedTime(task.ID); stored == nil || *stored != "09:30" {
		t.Fatalf("stored due_time = %v", stored)
	}
	insert := spy.lastInsert(t)
	if insert.Start.DateTime != "2026-08-19T09:30:00+02:00" || insert.Start.Date != "" {
		t.Fatalf("timed start = %+v", insert.Start)
	}
	if insert.End.DateTime != "2026-08-19T10:30:00+02:00" || insert.End.Date != "" {
		t.Fatalf("timed end = %+v", insert.End)
	}
	if insert.Start.TimeZone != "Europe/Amsterdam" {
		t.Fatalf("timed start zone = %q", insert.Start.TimeZone)
	}
	// on_day is not the manual-todo reminder; "1_day" before a real start is
	// a full day, not the all-day 09:00 heuristic.
	if got := insert.Reminders.Overrides[0].Minutes; got != 1440 {
		t.Fatalf("timed reminder = %d, want 1440", got)
	}

	// --- move the hour → the same event, updated --------------------------
	rec = patch(task.ID, `{"due_time":"18:15"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("patch due_time: status %d — %s", rec.Code, rec.Body.String())
	}
	if moved := decodeTask(rec); moved.DueTime == nil || *moved.DueTime != "18:15" {
		t.Fatalf("patched due_time = %v", moved.DueTime)
	}
	update := spy.lastUpdate(t)
	if update.Start.DateTime != "2026-08-19T18:15:00+02:00" || update.End.DateTime != "2026-08-19T19:15:00+02:00" {
		t.Fatalf("moved slot = %+v → %+v", update.Start, update.End)
	}

	// --- clear the hour → back to all-day ---------------------------------
	rec = patch(task.ID, `{"clear_due_time":true}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("clear due_time: status %d — %s", rec.Code, rec.Body.String())
	}
	if cleared := decodeTask(rec); cleared.DueTime != nil {
		t.Fatalf("cleared due_time = %v", *cleared.DueTime)
	}
	if stored := storedTime(task.ID); stored != nil {
		t.Fatalf("stored due_time after clear = %v", *stored)
	}
	update = spy.lastUpdate(t)
	if update.Start.Date != "2026-08-19" || update.Start.DateTime != "" || update.Start.TimeZone != "" {
		t.Fatalf("all-day start after clear = %+v", update.Start)
	}
	if update.End.Date != "2026-08-20" || update.End.DateTime != "" {
		t.Fatalf("all-day end after clear = %+v", update.End)
	}
	if got := update.Reminders.Overrides[0].Minutes; got != google.ReminderMinutes("1_day") {
		t.Fatalf("all-day reminder after clear = %d", got)
	}

	// --- an hour with no day is not a schedule ----------------------------
	rec = create(`{"title":"Nowhere","section":"admin","owner_member_id":"` + member +
		`","weight":1,"recurrence":"none","due_time":"09:30"}`)
	if rec.Code != http.StatusBadRequest || errCode(t, rec) != "bad_time" {
		t.Fatalf("time without a date: status %d — %s", rec.Code, rec.Body.String())
	}
	rec = create(`{"title":"Nonsense","section":"admin","owner_member_id":"` + member +
		`","weight":1,"recurrence":"none","due_on":"2026-08-19","due_time":"25:00"}`)
	if rec.Code != http.StatusBadRequest || errCode(t, rec) != "bad_time" {
		t.Fatalf("bad due_time: status %d — %s", rec.Code, rec.Body.String())
	}

	// --- dropping the date drops the hour with it -------------------------
	rec = patch(task.ID, `{"due_time":"07:45"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("re-time: status %d — %s", rec.Code, rec.Body.String())
	}
	rec = patch(task.ID, `{"clear_due_on":true}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("clear due_on: status %d — %s", rec.Code, rec.Body.String())
	}
	undated := decodeTask(rec)
	if undated.DueOn != nil || undated.DueTime != nil {
		t.Fatalf("undated todo kept a schedule: %v %v", undated.DueOn, undated.DueTime)
	}
	if stored := storedTime(task.ID); stored != nil {
		t.Fatalf("stored due_time after clearing the date = %v", *stored)
	}
}

// A slot booked directly in the shared Calendar arrives as a timed todo, and a
// time changed in Google surfaces for review exactly like a changed date does.
func TestCalendarSyncImportsTimedEvents(t *testing.T) {
	dbURL := testDBURL(t)
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
	mux.HandleFunc("/calendar/v3/calendars/even-cal/events", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"items": []map[string]any{
			{
				"id": "direct-slot", "summary": "Coffee with Marco", "status": "confirmed",
				"htmlLink": "https://calendar.google.com/direct-slot",
				"start":    map[string]string{"dateTime": "2026-08-09T10:00:00+02:00"},
			},
			{
				"id": "moved-slot", "summary": "Dentist", "status": "confirmed",
				"htmlLink": "https://calendar.google.com/moved-slot",
				"start":    map[string]string{"dateTime": "2026-08-19T16:45:00+02:00"},
			},
			{
				"id": "steady-slot", "summary": "Physio", "status": "confirmed",
				"htmlLink": "https://calendar.google.com/steady-slot",
				"start":    map[string]string{"dateTime": "2026-08-20T08:15:00+02:00"},
			},
		}})
	})
	fake := httptest.NewServer(mux)
	defer fake.Close()

	a := &API{DB: pool, Google: google.New("cid", "secret", "", fake.URL, fake.URL)}
	hh, member, week := seedCalHousehold(t, pool, "Timed Calendar Sync")
	connectCalendar(t, pool, hh, member)

	var movedID, steadyID string
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence,
			due_on, due_time, google_event_id, calendar_sync_state)
		values ($1, 'Dentist', 'admin', $2, 1, 'none', '2026-08-19', '09:30', 'moved-slot', 'synced')
		returning id`, hh, member).Scan(&movedID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence,
			due_on, due_time, google_event_id, calendar_sync_state)
		values ($1, 'Physio', 'admin', $2, 1, 'none', '2026-08-20', '08:15', 'steady-slot', 'synced')
		returning id`, hh, member).Scan(&steadyID); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: member, HouseholdID: hh, Household: "Timed Calendar Sync", WeekID: week}
	out, err := a.syncCalendar(ctx, m)
	if err != nil {
		t.Fatal(err)
	}
	if out.Imported != 1 || out.Updated != 1 || out.Unchanged != 1 {
		t.Fatalf("unexpected reconciliation: %+v", out)
	}

	var importedDue, importedTime, importedState string
	if err := pool.QueryRow(ctx, `
		select due_on::text, to_char(due_time, 'HH24:MI'), calendar_sync_state from tasks
		where household_id = $1 and google_event_id = 'direct-slot'`, hh).
		Scan(&importedDue, &importedTime, &importedState); err != nil {
		t.Fatal(err)
	}
	if importedDue != "2026-08-09" || importedTime != "10:00" || importedState != "synced" {
		t.Fatalf("imported slot = %q %q %q", importedDue, importedTime, importedState)
	}

	var movedTime, movedState string
	if err := pool.QueryRow(ctx, `
		select to_char(due_time, 'HH24:MI'), calendar_sync_state from tasks where id = $1`, movedID).
		Scan(&movedTime, &movedState); err != nil {
		t.Fatal(err)
	}
	if movedTime != "16:45" || movedState != "external_changed" {
		t.Fatalf("time changed in Google = %q %q", movedTime, movedState)
	}

	// An unchanged slot round-trips: the hour Even wrote comes back identical,
	// so nothing is flagged for review.
	var steadyTime, steadyState string
	if err := pool.QueryRow(ctx, `
		select to_char(due_time, 'HH24:MI'), calendar_sync_state from tasks where id = $1`, steadyID).
		Scan(&steadyTime, &steadyState); err != nil {
		t.Fatal(err)
	}
	if steadyTime != "08:15" || steadyState != "synced" {
		t.Fatalf("round-tripped slot = %q %q", steadyTime, steadyState)
	}
}
