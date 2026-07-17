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
	// Drafts: in-range pending, out-of-range pending, dismissed in-range.
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
	if len(resp.Items) != 3 {
		t.Fatalf("want 3 items, got %d: %+v", len(resp.Items), resp.Items)
	}
	// Same due date → drafts sort before tasks.
	if resp.Items[0].Kind != "draft" || resp.Items[0].Title != "Pay the energy bill" ||
		resp.Items[0].Category != "bills" || resp.Items[0].AmountCents == nil || *resp.Items[0].AmountCents != 11240 {
		t.Fatalf("draft item wrong: %+v", resp.Items[0])
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
	if msg := a.calendarEventForApproval(ctx, m, taskID, "Pay the bill", "VATTENFALL", &amount, &due, "1_day"); msg != "" {
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
	if msg := a.calendarEventForApproval(ctx, m, task2, "Second bill", "X", nil, &due, "on_day"); msg != "" {
		t.Fatalf("second approval: %s", msg)
	}
	if n := creates.Load().(int); n != 1 {
		t.Fatalf("calendar created %d times, want 1", n)
	}
	fmt.Println("shared calendar create/reuse verified")
}
