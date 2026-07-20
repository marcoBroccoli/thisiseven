package api

// Runs only with EVEN_TESTDB (compose db), like TestFullFlow.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
)

func seedCalHousehold(t *testing.T, pool *pgxpool.Pool, name string) (hh, member, week string) {
	t.Helper()
	ctx := context.Background()
	hh, member = newUUID(), newUUID()
	if _, err := pool.Exec(ctx, `insert into households (id, name, invite_code) values ($1,$2,$3)`,
		hh, name, strings.ToUpper(newUUID()[:6])); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `insert into members (id, household_id, user_id, display_name, color)
		values ($1,$2,$3,'Tester','clay')`, member, hh, newUUID()); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `insert into weeks (household_id, week_index, started_on)
		values ($1,1,current_date) returning id`, hh).Scan(&week); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `delete from households where id = $1`, hh)
	})
	return hh, member, week
}

func agendaRequest(m *Membership, query string) *http.Request {
	req := httptest.NewRequest(http.MethodGet, "/v1/calendar"+query, nil)
	return req.WithContext(context.WithValue(req.Context(), memberKey{}, m))
}

func TestCalendarAgenda(t *testing.T) {
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
	a := &API{DB: pool}

	hh, member, week := seedCalHousehold(t, pool, "Agenda Test")
	otherHH, otherMember, _ := seedCalHousehold(t, pool, "Other House")

	in := time.Now().In(Amsterdam).AddDate(0, 0, 3).Format("2006-01-02")
	out := time.Now().In(Amsterdam).AddDate(0, 0, 90).Format("2006-01-02")

	mustExec := func(sql string, args ...any) {
		t.Helper()
		if _, err := pool.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	// Gmail suggestions stay in review and never appear on the schedule.
	mustExec(`insert into drafts (household_id, from_label, subject, urgency, title, owner_member_id,
		amount_cents, due_on, reminder, created_by, category)
		values ($1,'VATTENFALL','s',2,'Pay the energy bill',$2, 11240, $3, '3_days', $2, 'bills')`,
		hh, member, in)
	mustExec(`insert into drafts (household_id, from_label, subject, urgency, title, owner_member_id,
		due_on, reminder, created_by)
		values ($1,'X','s',1,'Too far out',$2, $3, '1_day', $2)`, hh, member, out)
	mustExec(`insert into drafts (household_id, from_label, subject, urgency, title, owner_member_id,
		due_on, reminder, created_by, status)
		values ($1,'X','s',1,'Dismissed thing',$2, $3, '1_day', $2, 'dismissed')`, hh, member, in)
	// Isolation: the other household's pending draft must not leak.
	mustExec(`insert into drafts (household_id, from_label, subject, urgency, title, owner_member_id,
		due_on, reminder, created_by)
		values ($1,'X','s',1,'Foreign draft',$2, $3, '1_day', $2)`, otherHH, otherMember, in)

	// Tasks: open in-range, done in-range (open-week completion), archived, undated.
	var tOpen, tDone string
	if err := pool.QueryRow(ctx, `insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on)
		values ($1,'Confirm the dentist','admin',$2,2,'none',$3) returning id`, hh, member, in).Scan(&tOpen); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on)
		values ($1,'Water bill paid','admin',$2,2,'none',$3) returning id`, hh, member, in).Scan(&tDone); err != nil {
		t.Fatal(err)
	}
	mustExec(`insert into completions (task_id, week_id, member_id, weight)
		values ($1,$2,$3,2)`, tDone, week, member)
	mustExec(`insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on, archived_at)
		values ($1,'Old archived','chore',$2,1,'none',$3, now())`, hh, member, in)
	mustExec(`insert into tasks (household_id, title, section, owner_member_id, weight, recurrence)
		values ($1,'No due date','chore',$2,1,'none')`, hh, member)

	m := &Membership{MemberID: member, HouseholdID: hh, Household: "Agenda Test", WeekID: week}

	rec := httptest.NewRecorder()
	a.Calendar(rec, agendaRequest(m, ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	var resp struct {
		From  string             `json:"from"`
		To    string             `json:"to"`
		Items []CalendarItemJSON `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if len(resp.Items) != 2 {
		t.Fatalf("want 2 items, got %d: %+v", len(resp.Items), resp.Items)
	}
	byTitle := map[string]CalendarItemJSON{}
	for _, it := range resp.Items {
		byTitle[it.Title] = it
	}
	if it := byTitle["Confirm the dentist"]; it.Kind != "task" || it.Done == nil || *it.Done {
		t.Fatalf("open task wrong: %+v", it)
	}
	if it := byTitle["Water bill paid"]; it.Done == nil || !*it.Done {
		t.Fatalf("done task wrong: %+v", it)
	}
	if _, ok := byTitle["Pay the energy bill"]; ok {
		t.Fatal("pending Gmail suggestion leaked into the schedule")
	}

	// Bad inputs.
	rec = httptest.NewRecorder()
	a.Calendar(rec, agendaRequest(m, "?from=nope"))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("bad from: %d", rec.Code)
	}
	rec = httptest.NewRecorder()
	a.Calendar(rec, agendaRequest(m, "?from=2026-08-01&to=2026-07-01"))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("reversed range: %d", rec.Code)
	}
	// Span cap: 200 days clamps to 120.
	rec = httptest.NewRecorder()
	a.Calendar(rec, agendaRequest(m, "?from=2026-07-01&to=2027-01-17"))
	if rec.Code != http.StatusOK {
		t.Fatalf("cap: %d", rec.Code)
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.To != "2026-10-29" { // 2026-07-01 + 120d
		t.Fatalf("span cap: got to=%s", resp.To)
	}
}

func TestSharedCalendarCreation(t *testing.T) {
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

	var creates, lastEventCal atomic.Value
	creates.Store(0)
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 3600})
	})
	mux.HandleFunc("/calendar/v3/calendars", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Summary string `json:"summary"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		if !strings.Contains(body.Summary, "Cal Test") {
			t.Errorf("calendar summary %q missing household name", body.Summary)
		}
		creates.Store(creates.Load().(int) + 1)
		_ = json.NewEncoder(w).Encode(map[string]string{"id": "even-cal-123"})
	})
	mux.HandleFunc("/calendar/v3/calendars/", func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/calendar/v3/calendars/"), "/")
		lastEventCal.Store(parts[0])
		_ = json.NewEncoder(w).Encode(map[string]string{
			"id": "evt1", "htmlLink": "https://calendar.google.com/event?eid=evt1"})
	})
	fake := httptest.NewServer(mux)
	defer fake.Close()

	a := &API{DB: pool, Google: google.New("cid", "sec", "", fake.URL, fake.URL)}

	hh, member, _ := seedCalHousehold(t, pool, "Cal Test")
	if _, err := pool.Exec(ctx, `insert into google_accounts (household_id, email, refresh_token, client_kind, connected_by)
		values ($1,'t@example.com','rt','desktop',$2)`, hh, member); err != nil {
		t.Fatal(err)
	}
	var taskID string
	due := time.Now().In(Amsterdam).AddDate(0, 0, 5)
	if err := pool.QueryRow(ctx, `insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on)
		values ($1,'Pay the bill','admin',$2,2,'none',$3) returning id`, hh, member, due.Format("2006-01-02")).Scan(&taskID); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: member, HouseholdID: hh, Household: "Cal Test"}
	amount := int64(11240)
	if msg := a.publishTaskToCalendar(ctx, m, taskID, "Pay the bill", "VATTENFALL", &amount, &due, "1_day"); msg != "" {
		t.Fatalf("approval calendar error: %s", msg)
	}

	var calID string
	if err := pool.QueryRow(ctx, `select calendar_id from google_accounts where household_id = $1`, hh).Scan(&calID); err != nil {
		t.Fatal(err)
	}
	if calID != "even-cal-123" {
		t.Fatalf("calendar_id not persisted: %s", calID)
	}
	if got := lastEventCal.Load(); got != "even-cal-123" {
		t.Fatalf("event inserted into %v, want even-cal-123", got)
	}
	var url *string
	if err := pool.QueryRow(ctx, `select google_event_url from tasks where id = $1`, taskID).Scan(&url); err != nil {
		t.Fatal(err)
	}
	if url == nil || *url == "" {
		t.Fatal("task event url not recorded")
	}

	// Second approval must reuse the calendar, not create another.
	var task2 string
	if err := pool.QueryRow(ctx, `insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on)
		values ($1,'Second bill','admin',$2,2,'none',$3) returning id`, hh, member, due.Format("2006-01-02")).Scan(&task2); err != nil {
		t.Fatal(err)
	}
	if msg := a.publishTaskToCalendar(ctx, m, task2, "Second bill", "X", nil, &due, "on_day"); msg != "" {
		t.Fatalf("second approval: %s", msg)
	}
	if n := creates.Load().(int); n != 1 {
		t.Fatalf("calendar created %d times, want 1", n)
	}
	fmt.Println("shared calendar create/reuse verified")
}

func TestUpdateTaskClearsMappedCalendarEvent(t *testing.T) {
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

	var deletes atomic.Int32
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 3600})
	})
	mux.HandleFunc("/calendar/v3/calendars/even-cal/events/event-1", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodDelete {
			t.Errorf("method = %s, want DELETE", r.Method)
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		deletes.Add(1)
		w.WriteHeader(http.StatusNoContent)
	})
	fake := httptest.NewServer(mux)
	defer fake.Close()

	a := &API{DB: pool, Google: google.New("cid", "secret", "", fake.URL, fake.URL)}
	hh, member, week := seedCalHousehold(t, pool, "Clear calendar test")
	if _, err := pool.Exec(ctx, `
		insert into google_accounts (household_id, email, refresh_token, client_kind, connected_by, calendar_id)
		values ($1, 't@example.com', 'rt', 'desktop', $2, 'even-cal')`, hh, member); err != nil {
		t.Fatal(err)
	}
	var taskID string
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence,
			due_on, google_event_id, google_event_url, calendar_sync_state)
		values ($1, 'Book the dentist', 'admin', $2, 2, 'none', current_date + 7,
			'event-1', 'https://calendar.google.com/event?eid=event-1', 'synced')
		returning id`, hh, member).Scan(&taskID); err != nil {
		t.Fatal(err)
	}

	body := strings.NewReader(`{"clear_due_on":true}`)
	req := httptest.NewRequest(http.MethodPatch, "/v1/tasks/"+taskID, body)
	req.Header.Set("Content-Type", "application/json")
	m := &Membership{MemberID: member, HouseholdID: hh, Household: "Clear calendar test", WeekID: week}
	req = req.WithContext(context.WithValue(req.Context(), memberKey{}, m))
	rec := httptest.NewRecorder()
	a.UpdateTask(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	if deletes.Load() != 1 {
		t.Fatalf("calendar deletes = %d, want 1", deletes.Load())
	}
	var dueOn, eventID, eventURL *string
	var state string
	if err := pool.QueryRow(ctx, `
		select due_on::text, google_event_id, google_event_url, calendar_sync_state from tasks where id = $1`, taskID).
		Scan(&dueOn, &eventID, &eventURL, &state); err != nil {
		t.Fatal(err)
	}
	if dueOn != nil || eventID != nil || eventURL != nil || state != "not_scheduled" {
		t.Fatalf("task calendar mapping not cleared: due=%v event=%v url=%v state=%s", dueOn, eventID, eventURL, state)
	}
}

func TestResolveTaskCalendarActions(t *testing.T) {
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

	var restores, retries atomic.Int32
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 3600})
	})
	mux.HandleFunc("/calendar/v3/calendars/even-cal/events", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("restore method = %s, want POST", r.Method)
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		restores.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"id": "restored-event", "htmlLink": "https://calendar.google.com/restored"})
	})
	mux.HandleFunc("/calendar/v3/calendars/even-cal/events/retry-event", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			t.Errorf("retry method = %s, want PUT", r.Method)
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		retries.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]string{
			"id": "retry-event", "htmlLink": "https://calendar.google.com/retried"})
	})
	fake := httptest.NewServer(mux)
	defer fake.Close()

	a := &API{DB: pool, Google: google.New("cid", "secret", "", fake.URL, fake.URL)}
	hh, member, week := seedCalHousehold(t, pool, "Resolve calendar test")
	if _, err := pool.Exec(ctx, `
		insert into google_accounts (household_id, email, refresh_token, client_kind, connected_by, calendar_id)
		values ($1, 't@example.com', 'rt', 'desktop', $2, 'even-cal')`, hh, member); err != nil {
		t.Fatal(err)
	}
	var changedID, deletedID, retryID string
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence,
			due_on, google_event_id, calendar_sync_state)
		values ($1, 'Book the plumber', 'admin', $2, 1, 'none', current_date + 7,
			'changed-event', 'external_changed') returning id`, hh, member).Scan(&changedID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence,
			due_on, google_event_id, calendar_sync_state)
		values ($1, 'Confirm the dentist', 'admin', $2, 1, 'none', current_date + 8,
			'deleted-event', 'external_deleted') returning id`, hh, member).Scan(&deletedID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence,
			due_on, google_event_id, calendar_sync_state)
		values ($1, 'Pay electricity', 'admin', $2, 1, 'none', current_date + 9,
			'retry-event', 'retry_required') returning id`, hh, member).Scan(&retryID); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: member, HouseholdID: hh, Household: "Resolve calendar test", WeekID: week}
	resolve := func(taskID, action string) {
		t.Helper()
		req := httptest.NewRequest(http.MethodPost, "/v1/tasks/"+taskID+"/calendar/resolve",
			strings.NewReader(`{"action":"`+action+`"}`))
		req.Header.Set("Content-Type", "application/json")
		req = req.WithContext(context.WithValue(req.Context(), memberKey{}, m))
		rec := httptest.NewRecorder()
		a.ResolveTaskCalendar(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("resolve %s: status %d: %s", action, rec.Code, rec.Body.String())
		}
	}

	resolve(changedID, calendarResolutionAcknowledge)
	resolve(deletedID, calendarResolutionRestore)
	resolve(retryID, calendarResolutionRetry)

	var changedState, deletedState, retryState string
	var deletedEvent string
	if err := pool.QueryRow(ctx, `select calendar_sync_state from tasks where id = $1`, changedID).Scan(&changedState); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `select calendar_sync_state, google_event_id from tasks where id = $1`, deletedID).
		Scan(&deletedState, &deletedEvent); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `select calendar_sync_state from tasks where id = $1`, retryID).Scan(&retryState); err != nil {
		t.Fatal(err)
	}
	if changedState != "synced" || deletedState != "synced" || deletedEvent != "restored-event" || retryState != "synced" {
		t.Fatalf("unexpected states changed=%s deleted=%s event=%s retry=%s", changedState, deletedState, deletedEvent, retryState)
	}
	if restores.Load() != 1 || retries.Load() != 1 {
		t.Fatalf("Google calls restores=%d retries=%d", restores.Load(), retries.Load())
	}
}
