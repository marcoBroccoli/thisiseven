package api

// Leaving a household. A departure is soft: the member disappears from every
// "who lives here" answer, their open work is archived, the seat is free — and
// the history that names them survives, because a settled expense from March
// still happened. The last one out takes the household with them.
//
// Runs only with EVEN_TESTDB (a database named even_test), like the other
// integration suites.

import (
	"context"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/auth"
)

// leaveEnv is the shared fixture: a real server, a real pool, real GoTrue
// identities. `api` lets a suite hand in a Google-wired API instead of a bare
// one.
type leaveEnv struct {
	db     *pgxpool.Pool
	secret string
	url    string
}

func newLeaveEnv(t *testing.T, a *API) *leaveEnv {
	t.Helper()
	dbURL := testDBURL(t)
	secret := os.Getenv("EVEN_GOTRUE_JWT_SECRET")
	if secret == "" {
		t.Fatal("EVEN_GOTRUE_JWT_SECRET required")
	}
	db, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatal(err)
	}
	// Registered first so it runs LAST: t.Cleanup is LIFO and the fixture
	// deletes still need the pool.
	t.Cleanup(db.Close)
	if a == nil {
		a = &API{DB: db}
	} else {
		a.DB = db
	}
	srv := httptest.NewServer(Router(a, auth.NewVerifier([]byte(secret)), "http://127.0.0.1:1"))
	t.Cleanup(srv.Close)
	return &leaveEnv{db: db, secret: secret, url: srv.URL}
}

func (e *leaveEnv) user(t *testing.T, email string) *hClient {
	t.Helper()
	return seedUser(t, e.db, e.url, e.secret, email)
}

// createHousehold makes one and registers its teardown. The purge order
// mirrors LeaveHousehold's: a bare `delete from households` trips over the
// member references history holds.
func (e *leaveEnv) createHousehold(t *testing.T, c *hClient, name, displayName string) string {
	t.Helper()
	code, body := c.do("POST", "/v1/households", map[string]any{
		"name": name, "display_name": displayName})
	mustStatus(t, code, 201, "create "+name, body)
	id := body["id"].(string)
	t.Cleanup(func() {
		ctx := context.Background()
		tx, err := e.db.Begin(ctx)
		if err != nil {
			return
		}
		defer tx.Rollback(ctx)
		if err := purgeHousehold(ctx, tx, id); err == nil {
			_ = tx.Commit(ctx)
		}
	})
	return id
}

// memberIDOf is the caller's member row in one household (nil when they have
// none there any more).
func memberIDOf(t *testing.T, pool *pgxpool.Pool, householdID, email string) string {
	t.Helper()
	var id string
	if err := pool.QueryRow(context.Background(), `
		select m.id from members m join auth.users u on u.id = m.user_id
		where m.household_id = $1 and u.email = $2`, householdID, email).Scan(&id); err != nil {
		t.Fatalf("member row for %s: %v", email, err)
	}
	return id
}

func leave(t *testing.T, c *hClient, householdID string) (int, map[string]any) {
	t.Helper()
	return c.do("POST", "/v1/households/"+householdID+"/leave", nil)
}

// One partner walks out of a shared household: they vanish from it, their open
// work is archived, what they already did stays on the record, and the seat is
// free for the next person — including them, later.
func TestLeaveWithPartnerRemaining(t *testing.T) {
	env := newLeaveEnv(t, nil)
	ada := env.user(t, "ada.leave@example.com")
	umut := env.user(t, "umut.leave@example.com")
	zoe := env.user(t, "zoe.leave@example.com")

	hh := env.createHousehold(t, ada, "Leave Huis", "Ada")
	code, body := ada.do("GET", "/v1/households", nil)
	mustStatus(t, code, 200, "list before join", body)
	inviteCode := body["households"].([]any)[0].(map[string]any)["invite_code"].(string)
	code, body = umut.do("POST", "/v1/households/join", map[string]any{
		"invite_code": inviteCode, "display_name": "Umut"})
	mustStatus(t, code, 200, "umut joins", body)

	adaID := memberIDOf(t, env.db, hh, "ada.leave@example.com")
	umutID := memberIDOf(t, env.db, hh, "umut.leave@example.com")

	// Ada has one done chore (history) and one open todo (leaves with her);
	// Umut has an open todo of his own (stays).
	code, done := ada.in(hh).do("POST", "/v1/tasks", map[string]any{
		"title": "Ada dishes", "section": "chore",
		"owner_member_id": adaID, "weight": 2, "recurrence": "none"})
	mustStatus(t, code, 201, "ada task", done)
	code, body = ada.in(hh).do("POST", "/v1/tasks/"+done["id"].(string)+"/toggle", nil)
	mustStatus(t, code, 200, "ada toggles", body)
	code, open := ada.in(hh).do("POST", "/v1/tasks", map[string]any{
		"title": "Ada laundry", "section": "chore",
		"owner_member_id": adaID, "weight": 1, "recurrence": "weekly"})
	mustStatus(t, code, 201, "ada open task", open)
	code, umutTask := umut.in(hh).do("POST", "/v1/tasks", map[string]any{
		"title": "Umut bins", "section": "chore",
		"owner_member_id": umutID, "weight": 1, "recurrence": "weekly"})
	mustStatus(t, code, 201, "umut task", umutTask)

	// --- the departure -------------------------------------------------
	code, body = leave(t, ada, hh)
	mustStatus(t, code, 200, "ada leaves", body)
	if body["ok"] != true || body["household_deleted"] != false {
		t.Fatalf("leave response: %v", body)
	}

	// Ada is gone from every "who lives here" answer.
	code, me := ada.do("GET", "/v1/me", nil)
	mustStatus(t, code, 200, "ada me after leaving", me)
	if me["member"] != nil || me["household"] != nil {
		t.Fatalf("a leaver holds no household: %v", me)
	}
	hs, _ := householdList(t, ada)
	if len(hs) != 0 {
		t.Fatalf("a leaver lists no households: %v", hs)
	}
	// And every household-scoped route treats her as a stranger.
	for _, route := range []string{"/v1/summary", "/v1/money", "/v1/drafts"} {
		code, body = ada.in(hh).do("GET", route, nil)
		mustStatus(t, code, 403, "leaver on "+route, body)
		if body["error"].(map[string]any)["code"] != "not_in_household" {
			t.Fatalf("%s: wrong error code %v", route, body["error"])
		}
	}
	code, body = leave(t, ada, hh)
	mustStatus(t, code, 403, "leaving twice", body)

	// Umut carries on, alone.
	code, me = umut.do("GET", "/v1/me", nil)
	mustStatus(t, code, 200, "umut me", me)
	if me["household"].(map[string]any)["id"] != hh {
		t.Fatalf("umut lost his household: %v", me["household"])
	}
	if members := me["household"].(map[string]any)["members"].([]any); len(members) != 1 {
		t.Fatalf("the member list must drop the leaver: %v", members)
	}
	hs, _ = householdList(t, umut)
	if len(hs) != 1 || hs[0]["member_count"] != float64(1) {
		t.Fatalf("member_count should drop to 1: %v", hs)
	}
	if hs[0]["my_member_id"] != umutID {
		t.Fatalf("my_member_id: %v, want %s", hs[0]["my_member_id"], umutID)
	}

	// Ada's open work is archived; Umut's is untouched.
	if n := countRows(t, env.db,
		`select count(*) from tasks where owner_member_id = $1 and archived_at is null`,
		adaID); n != 0 {
		t.Fatalf("%d of the leaver's todos are still open", n)
	}
	if n := countRows(t, env.db,
		`select count(*) from tasks where owner_member_id = $1 and archived_at is null`,
		umutID); n != 1 {
		t.Fatalf("the partner's todos must survive: %d open", n)
	}
	// The history that names her stays exactly where it was.
	if n := countRows(t, env.db,
		`select count(*) from completions where member_id = $1`, adaID); n != 1 {
		t.Fatalf("completions history lost: %d rows", n)
	}
	if n := countRows(t, env.db,
		`select count(*) from members where id = $1 and left_at is not null`, adaID); n != 1 {
		t.Fatal("the member row should survive with left_at set")
	}

	// Summary shows only what is left, and the beam has no ghost pebbles.
	code, sum := umut.in(hh).do("GET", "/v1/summary", nil)
	mustStatus(t, code, 200, "umut summary", sum)
	if len(sum["pebbles"].([]any)) != 0 {
		t.Fatalf("archived work must leave the beam: %v", sum["pebbles"])
	}
	titles := []string{}
	for _, sec := range sum["sections"].([]any) {
		for _, tt := range sec.(map[string]any)["tasks"].([]any) {
			titles = append(titles, tt.(map[string]any)["title"].(string))
		}
	}
	if len(titles) != 1 || titles[0] != "Umut bins" {
		t.Fatalf("summary after the departure: %v", titles)
	}

	// The seat is free: a fresh invite is allowed straight away.
	code, body = umut.do("POST", "/v1/households/"+hh+"/invite",
		map[string]any{"email": "zoe.leave@example.com"})
	mustStatus(t, code, 201, "invite into the freed seat", body)
	_, ivs := householdList(t, zoe)
	if len(ivs) != 1 {
		t.Fatalf("zoe should see the invite: %v", ivs)
	}
	code, body = umut.do("DELETE", "/v1/households/"+hh+"/invite", nil)
	mustStatus(t, code, 200, "revoke so ada can come back", body)

	// --- coming back ----------------------------------------------------
	code, back := ada.do("POST", "/v1/households/join", map[string]any{
		"invite_code": inviteCode, "display_name": "Ada Again"})
	mustStatus(t, code, 200, "ada rejoins by code", back)
	if n := countRows(t, env.db,
		`select count(*) from members where household_id = $1 and user_id =
		 (select id from auth.users where email = $2)`,
		hh, "ada.leave@example.com"); n != 1 {
		t.Fatalf("rejoining must revive the seat, not add one: %d rows", n)
	}
	if got := memberIDOf(t, env.db, hh, "ada.leave@example.com"); got != adaID {
		t.Fatalf("rejoined member id = %s, want the revived %s", got, adaID)
	}
	var seen bool
	for _, mm := range back["members"].([]any) {
		m := mm.(map[string]any)
		if m["id"] != adaID {
			continue
		}
		seen = true
		if m["display_name"] != "Ada Again" {
			t.Fatalf("a return rewrites the name: %v", m)
		}
		// Umut wears pine, so the free half of the pair is terracotta.
		if m["color"] != defaultCreatorColor {
			t.Fatalf("returning member should take the free colour: %v", m)
		}
	}
	if !seen {
		t.Fatalf("the revived member is missing from the household: %v", back["members"])
	}
	// Her archived work stays archived — a return is a new start.
	if n := countRows(t, env.db,
		`select count(*) from tasks where owner_member_id = $1 and archived_at is null`,
		adaID); n != 0 {
		t.Fatalf("a return should not resurrect archived todos: %d", n)
	}
}

// Nobody left to keep the lights on: the household and everything in it goes,
// including the rows that reference members and would block a naive cascade.
func TestLeaveLastMemberDeletesHousehold(t *testing.T) {
	env := newLeaveEnv(t, nil)
	ada := env.user(t, "ada.last@example.com")
	umut := env.user(t, "umut.last@example.com")

	hh := env.createHousehold(t, ada, "Last Huis", "Ada")
	code, body := ada.do("GET", "/v1/households", nil)
	mustStatus(t, code, 200, "list", body)
	inviteCode := body["households"].([]any)[0].(map[string]any)["invite_code"].(string)
	code, body = umut.do("POST", "/v1/households/join", map[string]any{
		"invite_code": inviteCode, "display_name": "Umut"})
	mustStatus(t, code, 200, "umut joins", body)

	adaID := memberIDOf(t, env.db, hh, "ada.last@example.com")
	umutID := memberIDOf(t, env.db, hh, "umut.last@example.com")

	// Fill the household with every shape that points at a member: a done
	// chore (completion), a settled expense (settlement), an appreciation and
	// a trade.
	code, task := ada.in(hh).do("POST", "/v1/tasks", map[string]any{
		"title": "Ada cooking", "section": "chore",
		"owner_member_id": adaID, "weight": 2, "recurrence": "none"})
	mustStatus(t, code, 201, "task", task)
	code, body = ada.in(hh).do("POST", "/v1/tasks/"+task["id"].(string)+"/toggle", nil)
	mustStatus(t, code, 200, "toggle", body)
	code, body = ada.in(hh).do("POST", "/v1/expenses", map[string]any{
		"title": "Groceries", "amount_cents": 4000,
		"paid_by_member_id": adaID, "incurred_on": dateStr(today())})
	mustStatus(t, code, 201, "expense", body)
	code, body = ada.in(hh).do("POST", "/v1/settle", nil)
	mustStatus(t, code, 200, "settle", body)
	code, body = ada.in(hh).do("PUT", "/v1/appreciations/mine", map[string]any{
		"body": "thank you", "said": true})
	mustStatus(t, code, 200, "appreciation", body)
	code, trade := umut.in(hh).do("POST", "/v1/trades", map[string]any{
		"task_id": task["id"].(string)})
	mustStatus(t, code, 201, "trade", trade)

	code, body = leave(t, umut, hh)
	mustStatus(t, code, 200, "umut leaves first", body)
	if body["household_deleted"] != false {
		t.Fatalf("one member is still in: %v", body)
	}
	if n := countRows(t, env.db, `select count(*) from households where id = $1`, hh); n != 1 {
		t.Fatal("the household must survive while somebody lives there")
	}

	code, body = leave(t, ada, hh)
	mustStatus(t, code, 200, "ada leaves last", body)
	if body["household_deleted"] != true {
		t.Fatalf("the last one out deletes the household: %v", body)
	}
	if n := countRows(t, env.db, `select count(*) from households where id = $1`, hh); n != 0 {
		t.Fatal("the household row is still there")
	}
	for _, table := range []string{"members", "weeks", "tasks", "expenses",
		"settlements", "trades", "drafts", "processed_emails", "household_invites"} {
		if n := countRows(t, env.db,
			`select count(*) from `+table+` where household_id = $1`, hh); n != 0 {
			t.Fatalf("%s rows survived the purge: %d", table, n)
		}
	}
	if n := countRows(t, env.db,
		`select count(*) from completions where member_id = any($1::uuid[])`,
		[]string{adaID, umutID}); n != 0 {
		t.Fatalf("completions survived the purge: %d", n)
	}
	// Nothing to hold on to: the caller now has no household at all.
	code, me := ada.do("GET", "/v1/me", nil)
	mustStatus(t, code, 200, "me after the household is gone", me)
	if me["household"] != nil {
		t.Fatalf("household should be gone: %v", me["household"])
	}
}

// A household you do not live in is not yours to leave.
func TestLeaveHouseholdYouAreNotIn(t *testing.T) {
	env := newLeaveEnv(t, nil)
	ada := env.user(t, "ada.stranger@example.com")
	zoe := env.user(t, "zoe.stranger@example.com")
	hh := env.createHousehold(t, ada, "Stranger Huis", "Ada")

	code, body := leave(t, zoe, hh)
	mustStatus(t, code, 403, "stranger leaves", body)
	if body["error"].(map[string]any)["code"] != "not_in_household" {
		t.Fatalf("wrong error code: %v", body["error"])
	}
	code, body = zoe.do("POST", "/v1/households/not-a-uuid/leave", nil)
	mustStatus(t, code, 403, "nonsense household id", body)
	// The household is untouched.
	if n := countRows(t, env.db,
		`select count(*) from members where household_id = $1 and left_at is null`, hh); n != 1 {
		t.Fatalf("the household lost a member to a stranger's request: %d", n)
	}
}

// Leaving carries the whole disconnect with it: the shared calendar is handed
// to the partner while the leaver's token still works, the token goes, and
// their mailbox is flushed. Their dated todos leave the calendar too, so the
// next sync cannot import them back as somebody else's work.
func TestLeaveDisconnectsGoogleAndHandsOverCalendar(t *testing.T) {
	fake := newFakeGoogle(t)
	a := fake.api(nil)
	env := newLeaveEnv(t, a)
	ctx := context.Background()
	ada := env.user(t, "ada.google@example.com")
	umut := env.user(t, "umut.google@example.com")

	hh := env.createHousehold(t, ada, "Google Huis", "Ada")
	code, body := ada.do("GET", "/v1/households", nil)
	mustStatus(t, code, 200, "list", body)
	inviteCode := body["households"].([]any)[0].(map[string]any)["invite_code"].(string)
	code, body = umut.do("POST", "/v1/households/join", map[string]any{
		"invite_code": inviteCode, "display_name": "Umut"})
	mustStatus(t, code, 200, "umut joins", body)

	adaID := memberIDOf(t, env.db, hh, "ada.google@example.com")
	umutID := memberIDOf(t, env.db, hh, "umut.google@example.com")

	// Both connected; Ada owns the shared calendar and has a dated todo on it.
	connectGoogle(t, env.db, hh, adaID, "ada@example.com")
	connectGoogle(t, env.db, hh, umutID, "umut@example.com")
	if _, err := env.db.Exec(ctx, `update households set calendar_id = 'shared-cal',
		calendar_owner_member_id = $1 where id = $2`, adaID, hh); err != nil {
		t.Fatal(err)
	}
	seedDraft(t, env.db, hh, adaID, "Ada water bill", "pending")
	seedDraft(t, env.db, hh, umutID, "Umut insurance", "pending")
	seedProcessedEmail(t, env.db, hh, adaID, "ada-msg-1")
	seedProcessedEmail(t, env.db, hh, umutID, "umut-msg-1")
	var datedTask string
	if err := env.db.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight,
			recurrence, due_on, google_event_id, google_event_url, calendar_sync_state)
		values ($1,'Ada dentist','admin',$2,1,'none',current_date + 3,'evt-ada',
			'https://calendar.google.com/event?eid=evt-ada','synced')
		returning id`, hh, adaID).Scan(&datedTask); err != nil {
		t.Fatal(err)
	}

	code, body = leave(t, ada, hh)
	mustStatus(t, code, 200, "ada leaves with google connected", body)

	// The token is gone; the partner's is not.
	if n := countRows(t, env.db,
		`select count(*) from google_accounts where member_id = $1`, adaID); n != 0 {
		t.Fatal("the leaver's Google connection survived")
	}
	if n := countRows(t, env.db,
		`select count(*) from google_accounts where member_id = $1`, umutID); n != 1 {
		t.Fatal("the partner's Google connection must be untouched")
	}
	// Their inbox is emptied, mailbox by mailbox.
	if n := countRows(t, env.db,
		`select count(*) from drafts where source_member_id = $1`, adaID); n != 0 {
		t.Fatal("the leaver's drafts were not flushed")
	}
	if n := countRows(t, env.db,
		`select count(*) from drafts where source_member_id = $1`, umutID); n != 1 {
		t.Fatal("the partner's drafts must survive")
	}
	if n := countRows(t, env.db,
		`select count(*) from processed_emails where member_id = $1`, adaID); n != 0 {
		t.Fatal("the leaver's processed-email verdicts were not flushed")
	}
	// The calendar moved to the remaining partner before the token died.
	_, owner := readCalendarState(t, env.db, hh)
	if owner != umutID {
		t.Fatalf("calendar owner = %s, want the remaining partner %s", owner, umutID)
	}
	if roles := fake.roles(); len(roles) == 0 || roles[0] != "owner" {
		t.Fatalf("handover should have asked Google for owner first: %v", roles)
	}
	// And their dated todo is archived and off the calendar.
	var archived *string
	var eventID *string
	if err := env.db.QueryRow(ctx,
		`select archived_at::text, google_event_id from tasks where id = $1`, datedTask).
		Scan(&archived, &eventID); err != nil {
		t.Fatal(err)
	}
	if archived == nil {
		t.Fatal("the leaver's dated todo should be archived")
	}
	if eventID != nil {
		t.Fatalf("the calendar mapping should be cleared, got %v", *eventID)
	}
}
