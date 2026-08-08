package api

// Owner-only writes. Runs only with EVEN_TESTDB (compose db), like TestFullFlow.
//
// Both partners see every todo — the beam only reads honestly when both sides
// are visible — but completing, editing and removing one belongs to the person
// it is assigned to. Creating work for the other stays allowed, and a Trade is
// the sanctioned way to move an existing todo across.

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// seedCouple returns a household with two members and an open week.
func seedCouple(t *testing.T, pool *pgxpool.Pool, name string) (hh, mine, theirs, week string) {
	t.Helper()
	ctx := context.Background()
	hh, mine, theirs = newUUID(), newUUID(), newUUID()
	if _, err := pool.Exec(ctx, `insert into households (id, name, invite_code) values ($1,$2,$3)`,
		hh, name, strings.ToUpper(newUUID()[:6])); err != nil {
		t.Fatal(err)
	}
	for id, display := range map[string]string{mine: "Umur", theirs: "Beste"} {
		if _, err := pool.Exec(ctx, `insert into members (id, household_id, user_id, display_name, color)
			values ($1,$2,$3,$4,'clay')`, id, hh, newUUID(), display); err != nil {
			t.Fatal(err)
		}
	}
	if err := pool.QueryRow(ctx, `insert into weeks (household_id, week_index, started_on)
		values ($1,1,current_date) returning id`, hh).Scan(&week); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `delete from households where id = $1`, hh)
	})
	return hh, mine, theirs, week
}

// taskRequest wires the chi URL param the task handlers read, so a direct
// handler call resolves the same id the router would.
func taskRequest(m *Membership, method, path, taskID, body string) *http.Request {
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, path, r)
	req.Header.Set("Content-Type", "application/json")
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("id", taskID)
	ctx := context.WithValue(req.Context(), chi.RouteCtxKey, rctx)
	return req.WithContext(context.WithValue(ctx, memberKey{}, m))
}

func errCode(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var body struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("error body %q: %v", rec.Body.String(), err)
	}
	return body.Error.Code
}

func TestTaskWritesAreOwnerOnly(t *testing.T) {
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

	hh, mine, theirs, week := seedCouple(t, pool, "Ownership Test")
	owner := &Membership{MemberID: mine, HouseholdID: hh, Household: "Ownership Test",
		WeekID: week, PartnerID: theirs, PartnerName: "Beste"}
	partner := &Membership{MemberID: theirs, HouseholdID: hh, Household: "Ownership Test",
		WeekID: week, PartnerID: mine, PartnerName: "Umur"}

	newTask := func(title, ownerID string) string {
		t.Helper()
		var id string
		if err := pool.QueryRow(ctx, `
			insert into tasks (household_id, title, section, owner_member_id, weight, recurrence)
			values ($1, $2, 'chore', $3, 2, 'none') returning id`, hh, title, ownerID).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	call := func(h http.HandlerFunc, m *Membership, method, taskID, body string) *httptest.ResponseRecorder {
		t.Helper()
		rec := httptest.NewRecorder()
		h(rec, taskRequest(m, method, "/v1/tasks/"+taskID, taskID, body))
		return rec
	}
	mustForbidden := func(rec *httptest.ResponseRecorder, what string) {
		t.Helper()
		if rec.Code != http.StatusForbidden {
			t.Fatalf("%s: status %d, want 403 — %s", what, rec.Code, rec.Body.String())
		}
		if code := errCode(t, rec); code != "not_owner" {
			t.Fatalf("%s: error code %q, want not_owner", what, code)
		}
	}

	// --- toggle -----------------------------------------------------------
	toggleTask := newTask("Empty the dishwasher", mine)

	mustForbidden(call(a.ToggleTask, partner, http.MethodPost, toggleTask, ""), "partner toggle")
	var completions int
	if err := pool.QueryRow(ctx, `select count(*) from completions where task_id = $1`, toggleTask).
		Scan(&completions); err != nil {
		t.Fatal(err)
	}
	if completions != 0 {
		t.Fatalf("refused toggle still dropped a pebble: %d completions", completions)
	}

	rec := call(a.ToggleTask, owner, http.MethodPost, toggleTask, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("owner toggle: status %d — %s", rec.Code, rec.Body.String())
	}
	var toggled TaskJSON
	if err := json.Unmarshal(rec.Body.Bytes(), &toggled); err != nil {
		t.Fatal(err)
	}
	if !toggled.Done {
		t.Fatal("owner toggle should mark the todo done")
	}

	// --- edit -------------------------------------------------------------
	editTask := newTask("Book the plumber", mine)

	mustForbidden(call(a.UpdateTask, partner, http.MethodPatch, editTask,
		`{"title":"Not yours to rename"}`), "partner edit")
	// Nor by claiming it in the body — the owner is read from the stored row.
	mustForbidden(call(a.UpdateTask, partner, http.MethodPatch, editTask,
		`{"owner_member_id":"`+theirs+`"}`), "partner self-assign")
	var title string
	if err := pool.QueryRow(ctx, `select title from tasks where id = $1`, editTask).Scan(&title); err != nil {
		t.Fatal(err)
	}
	if title != "Book the plumber" {
		t.Fatalf("refused edit changed the todo: %q", title)
	}

	rec = call(a.UpdateTask, owner, http.MethodPatch, editTask, `{"title":"Book the plumber (Tue)"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("owner edit: status %d — %s", rec.Code, rec.Body.String())
	}

	// --- reassign: the owner may hand their own todo over ------------------
	rec = call(a.UpdateTask, owner, http.MethodPatch, editTask, `{"owner_member_id":"`+theirs+`"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("owner reassign: status %d — %s", rec.Code, rec.Body.String())
	}
	var nowOwnedBy string
	if err := pool.QueryRow(ctx, `select owner_member_id from tasks where id = $1`, editTask).
		Scan(&nowOwnedBy); err != nil {
		t.Fatal(err)
	}
	if !strings.EqualFold(nowOwnedBy, theirs) {
		t.Fatalf("reassign did not land: owner = %s, want %s", nowOwnedBy, theirs)
	}
	// …and loses the right to it the moment it is theirs.
	mustForbidden(call(a.UpdateTask, owner, http.MethodPatch, editTask,
		`{"title":"Taking it back"}`), "edit after handing over")
	mustForbidden(call(a.ToggleTask, owner, http.MethodPost, editTask, ""), "toggle after handing over")
	// The new owner can.
	rec = call(a.UpdateTask, partner, http.MethodPatch, editTask, `{"title":"Mine now"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("new owner edit: status %d — %s", rec.Code, rec.Body.String())
	}

	// --- delete -----------------------------------------------------------
	deleteTask := newTask("Water the plants", mine)

	mustForbidden(call(a.DeleteTask, partner, http.MethodDelete, deleteTask, ""), "partner delete")
	var archived *string
	if err := pool.QueryRow(ctx, `select archived_at::text from tasks where id = $1`, deleteTask).
		Scan(&archived); err != nil {
		t.Fatal(err)
	}
	if archived != nil {
		t.Fatal("refused delete still archived the todo")
	}

	rec = call(a.DeleteTask, owner, http.MethodDelete, deleteTask, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("owner delete: status %d — %s", rec.Code, rec.Body.String())
	}
	if err := pool.QueryRow(ctx, `select archived_at::text from tasks where id = $1`, deleteTask).
		Scan(&archived); err != nil {
		t.Fatal(err)
	}
	if archived == nil {
		t.Fatal("owner delete should archive the todo")
	}

	// --- calendar resolve -------------------------------------------------
	var calendarTask string
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence,
			due_on, google_event_id, calendar_sync_state)
		values ($1, 'Confirm the dentist', 'admin', $2, 1, 'none', current_date + 7,
			'changed-event', 'external_changed') returning id`, hh, mine).Scan(&calendarTask); err != nil {
		t.Fatal(err)
	}
	mustForbidden(call(a.ResolveTaskCalendar, partner, http.MethodPost, calendarTask,
		`{"action":"acknowledge"}`), "partner calendar resolve")
	rec = call(a.ResolveTaskCalendar, owner, http.MethodPost, calendarTask, `{"action":"acknowledge"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("owner calendar resolve: status %d — %s", rec.Code, rec.Body.String())
	}

	// --- creating work FOR the partner stays allowed -----------------------
	rec = httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/tasks",
		strings.NewReader(`{"title":"Call the landlord","section":"admin","owner_member_id":"`+
			theirs+`","weight":1,"recurrence":"none"}`))
	req.Header.Set("Content-Type", "application/json")
	a.CreateTask(rec, req.WithContext(context.WithValue(req.Context(), memberKey{}, owner)))
	if rec.Code != http.StatusCreated {
		t.Fatalf("create for partner: status %d — %s", rec.Code, rec.Body.String())
	}
	var created TaskJSON
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	if !strings.EqualFold(created.OwnerMemberID, theirs) {
		t.Fatalf("created task owner = %s, want %s", created.OwnerMemberID, theirs)
	}
	// But having created it does not make it mine to finish.
	mustForbidden(call(a.ToggleTask, owner, http.MethodPost, created.ID, ""), "toggle a todo I sent over")
}
