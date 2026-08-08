package api

// Shared-calendar mirror: ownership, the partner's one-tap add, and the
// ownership handover on disconnect. Runs only with EVEN_TESTDB (compose db),
// against a fake Google HTTP server like calendar_test.go.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
)

func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dbURL := testDBURL(t)
	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// seedPartner adds the second member of a household (no Google connection).
func seedPartner(t *testing.T, pool *pgxpool.Pool, householdID string) string {
	t.Helper()
	id := newUUID()
	if _, err := pool.Exec(context.Background(),
		`insert into members (id, household_id, user_id, display_name, color)
		 values ($1,$2,$3,'Partner','pine')`, id, householdID, newUUID()); err != nil {
		t.Fatal(err)
	}
	return id
}

func connectGoogle(t *testing.T, pool *pgxpool.Pool, householdID, memberID, email string) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`insert into google_accounts (household_id, member_id, email, refresh_token, client_kind, connected_by)
		 values ($1,$2,$3,'rt','desktop',$2)`, householdID, memberID, email); err != nil {
		t.Fatal(err)
	}
}

func calendarRequest(m *Membership, method, path, body string) *http.Request {
	var req *http.Request
	if body == "" {
		req = httptest.NewRequest(method, path, nil)
	} else {
		req = httptest.NewRequest(method, path, strings.NewReader(body))
	}
	return req.WithContext(context.WithValue(req.Context(), memberKey{}, m))
}

func readCalendarState(t *testing.T, pool *pgxpool.Pool, householdID string) (string, string) {
	t.Helper()
	var calID string
	var owner *string
	if err := pool.QueryRow(context.Background(),
		`select calendar_id, calendar_owner_member_id from households where id = $1`,
		householdID).Scan(&calID, &owner); err != nil {
		t.Fatal(err)
	}
	if owner == nil {
		return calID, ""
	}
	return calID, *owner
}

// fakeGoogle is one configurable stand-in for the Calendar API: it records the
// ACL / CalendarList traffic the mirror depends on and can be told to refuse
// roles (owner-ACL blocked) or scopes (403 insufficientPermissions).
type fakeGoogle struct {
	server *httptest.Server

	aclRoles     atomic.Value // []string, roles Google was asked to grant
	aclDeletes   atomic.Int32
	listInserts  atomic.Int32
	calCreates   atomic.Int32
	calDeletes   atomic.Int32
	eventInserts atomic.Int32

	refuseRoles  map[string]bool // role → refuse with 403 forbiddenForNonOrganizer
	scopeDenied  bool            // every calendar call answers 403 insufficientPermissions
	newCalendars []string        // ids handed out by create, in order
	createIndex  atomic.Int32
	// beforeACL runs on every acl call — used to assert ordering against the DB.
	beforeACL func(role string)
}

func newFakeGoogle(t *testing.T) *fakeGoogle {
	t.Helper()
	f := &fakeGoogle{refuseRoles: map[string]bool{}}
	f.aclRoles.Store([]string{})
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 3600})
	})
	deny := func(w http.ResponseWriter) {
		w.WriteHeader(http.StatusForbidden)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{
			"code": 403, "message": "Request had insufficient authentication scopes.",
			"errors": []map[string]string{{"reason": "insufficientPermissions"}},
		}})
	}
	mux.HandleFunc("/calendar/v3/users/me/calendarList", func(w http.ResponseWriter, r *http.Request) {
		if f.scopeDenied {
			deny(w)
			return
		}
		f.listInserts.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]string{"id": "listed"})
	})
	mux.HandleFunc("/calendar/v3/calendars", func(w http.ResponseWriter, _ *http.Request) {
		if f.scopeDenied {
			deny(w)
			return
		}
		i := int(f.createIndex.Add(1)) - 1
		id := fmt.Sprintf("new-cal-%d", i+1)
		if i < len(f.newCalendars) {
			id = f.newCalendars[i]
		}
		f.calCreates.Add(1)
		_ = json.NewEncoder(w).Encode(map[string]string{"id": id})
	})
	mux.HandleFunc("/calendar/v3/calendars/", func(w http.ResponseWriter, r *http.Request) {
		rest := strings.TrimPrefix(r.URL.Path, "/calendar/v3/calendars/")
		parts := strings.Split(rest, "/")
		if f.scopeDenied {
			deny(w)
			return
		}
		switch {
		case len(parts) >= 2 && parts[1] == "acl":
			var body struct {
				Role string `json:"role"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			if r.Method == http.MethodDelete {
				f.aclDeletes.Add(1)
				w.WriteHeader(http.StatusNoContent)
				return
			}
			if f.beforeACL != nil {
				f.beforeACL(body.Role)
			}
			f.aclRoles.Store(append(f.aclRoles.Load().([]string), body.Role))
			if f.refuseRoles[body.Role] {
				w.WriteHeader(http.StatusForbidden)
				_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]any{
					"code": 403, "message": "Cannot change the organizer of an event.",
					"errors": []map[string]string{{"reason": "forbiddenForNonOrganizer"}},
				}})
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"id": "rule", "role": body.Role})
		case len(parts) >= 2 && parts[1] == "events":
			id := fmt.Sprintf("evt%d", f.eventInserts.Add(1))
			_ = json.NewEncoder(w).Encode(map[string]string{
				"id": id, "htmlLink": "https://calendar.google.com/event?eid=" + id})
		case r.Method == http.MethodDelete:
			f.calDeletes.Add(1)
			w.WriteHeader(http.StatusNoContent)
		default:
			_ = json.NewEncoder(w).Encode(map[string]string{"id": parts[0]})
		}
	})
	f.server = httptest.NewServer(mux)
	t.Cleanup(f.server.Close)
	return f
}

func (f *fakeGoogle) roles() []string { return f.aclRoles.Load().([]string) }

func (f *fakeGoogle) api(pool *pgxpool.Pool) *API {
	return &API{DB: pool, Google: google.New("cid", "sec", "", f.server.URL, f.server.URL)}
}

// A calendar created by Even belongs to the member whose token created it —
// that is the account Google will accept future writes from.
func TestCalendarCreateRecordsOwner(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	fake.newCalendars = []string{"owned-cal"}
	a := fake.api(pool)

	hh, member, _ := seedCalHousehold(t, pool, "Owner Test")
	connectGoogle(t, pool, hh, member, "owner@example.com")

	due := time.Now().In(Amsterdam).AddDate(0, 0, 4)
	var taskID string
	if err := pool.QueryRow(ctx, `insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on)
		values ($1,'Pay the bill','admin',$2,2,'none',$3) returning id`,
		hh, member, due.Format("2006-01-02")).Scan(&taskID); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: member, HouseholdID: hh, Household: "Owner Test"}
	if msg := a.publishTaskToCalendar(ctx, m, taskID, "Pay the bill", "", nil, &due, "1_day"); msg != "" {
		t.Fatalf("publish: %s", msg)
	}

	calID, owner := readCalendarState(t, pool, hh)
	if calID != "owned-cal" || owner != member {
		t.Fatalf("calendar=%s owner=%s, want owned-cal / %s", calID, owner, member)
	}
	if !a.calendarListedFor(ctx, member) {
		t.Fatal("the owner must count as already listed — nothing to add")
	}
}

// The partner's one-tap confirm: reader ACL on the owner's token, CalendarList
// insert on theirs. Never writer — the mirror is read-only in Google.
func TestCalendarAddGrantsReaderAndLists(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	a := fake.api(pool)

	hh, owner, _ := seedCalHousehold(t, pool, "Add Test")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, owner, "owner@example.com")
	connectGoogle(t, pool, hh, partner, "partner@example.com")
	if _, err := pool.Exec(ctx, `update households set calendar_id = 'shared-cal',
		calendar_owner_member_id = $1 where id = $2`, owner, hh); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: partner, HouseholdID: hh, Household: "Add Test", PartnerID: owner}
	rec := httptest.NewRecorder()
	a.GoogleCalendarAdd(rec, calendarRequest(m, http.MethodPost, "/v1/google/calendar/add", ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	var out struct {
		CalendarID string `json:"calendar_id"`
		Listed     bool   `json:"listed"`
		Owner      bool   `json:"owner"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if out.CalendarID != "shared-cal" || !out.Listed || out.Owner {
		t.Fatalf("response %+v", out)
	}
	if roles := fake.roles(); len(roles) != 1 || roles[0] != google.ACLRoleReader {
		t.Fatalf("acl roles = %v, want [reader]", roles)
	}
	if fake.listInserts.Load() != 1 {
		t.Fatalf("calendarList inserts = %d, want 1", fake.listInserts.Load())
	}
	if !a.calendarListedFor(ctx, partner) {
		t.Fatal("the subscription was not recorded for the partner")
	}

	// calendar-info now offers nothing to add, and the owner never sees the CTA.
	info := func(mm *Membership) map[string]any {
		rec := httptest.NewRecorder()
		a.GoogleCalendarInfo(rec, calendarRequest(mm, http.MethodGet, "/v1/google/calendar-info", ""))
		if rec.Code != http.StatusOK {
			t.Fatalf("calendar-info %d: %s", rec.Code, rec.Body.String())
		}
		var body map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		return body
	}
	if got := info(m); got["can_add"] != false || got["listed"] != true || got["owner"] != false {
		t.Fatalf("partner info %+v", got)
	}
	ownerM := &Membership{MemberID: owner, HouseholdID: hh, Household: "Add Test", PartnerID: partner}
	if got := info(ownerM); got["owner"] != true || got["can_add"] != false {
		t.Fatalf("owner info %+v", got)
	}
}

func TestCalendarAddConflicts(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	a := fake.api(pool)

	hh, owner, _ := seedCalHousehold(t, pool, "Add Conflicts")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, owner, "owner@example.com")
	connectGoogle(t, pool, hh, partner, "partner@example.com")

	partnerM := &Membership{MemberID: partner, HouseholdID: hh, Household: "Add Conflicts", PartnerID: owner}
	ownerM := &Membership{MemberID: owner, HouseholdID: hh, Household: "Add Conflicts", PartnerID: partner}

	// No calendar yet → not_ready.
	rec := httptest.NewRecorder()
	a.GoogleCalendarAdd(rec, calendarRequest(partnerM, http.MethodPost, "/v1/google/calendar/add", ""))
	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), "not_ready") {
		t.Fatalf("want 409 not_ready, got %d: %s", rec.Code, rec.Body.String())
	}

	if _, err := pool.Exec(ctx, `update households set calendar_id = 'shared-cal',
		calendar_owner_member_id = $1 where id = $2`, owner, hh); err != nil {
		t.Fatal(err)
	}

	// The owner has nothing to add.
	rec = httptest.NewRecorder()
	a.GoogleCalendarAdd(rec, calendarRequest(ownerM, http.MethodPost, "/v1/google/calendar/add", ""))
	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), "already_owner") {
		t.Fatalf("want 409 already_owner, got %d: %s", rec.Code, rec.Body.String())
	}

	// A member with no Google of their own cannot subscribe anything.
	if _, err := pool.Exec(ctx, `delete from google_accounts where member_id = $1`, partner); err != nil {
		t.Fatal(err)
	}
	rec = httptest.NewRecorder()
	a.GoogleCalendarAdd(rec, calendarRequest(partnerM, http.MethodPost, "/v1/google/calendar/add", ""))
	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), "not_connected") {
		t.Fatalf("want 409 not_connected, got %d: %s", rec.Code, rec.Body.String())
	}
}

// A grant made before the scope bump fails loudly: the app must send the user
// back through consent, never report a share that did not happen.
func TestCalendarAddStaleScopeFailsCleanly(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	fake.scopeDenied = true
	a := fake.api(pool)

	hh, owner, _ := seedCalHousehold(t, pool, "Stale Scope")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, owner, "owner@example.com")
	connectGoogle(t, pool, hh, partner, "partner@example.com")
	if _, err := pool.Exec(ctx, `update households set calendar_id = 'shared-cal',
		calendar_owner_member_id = $1 where id = $2`, owner, hh); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: partner, HouseholdID: hh, Household: "Stale Scope", PartnerID: owner}
	rec := httptest.NewRecorder()
	a.GoogleCalendarAdd(rec, calendarRequest(m, http.MethodPost, "/v1/google/calendar/add", ""))
	if rec.Code != http.StatusConflict {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "reconnect") {
		t.Fatalf("stale scope must ask for a reconnect, got %s", rec.Body.String())
	}
	if a.calendarListedFor(ctx, partner) {
		t.Fatal("a failed add must not be recorded as listed")
	}
}

// The happy handover: Google accepts an owner-role ACL, so the calendar id
// survives — and the transfer runs while the leaving member's token still
// exists (asserted from inside the fake, mid-call).
func TestOwnerDisconnectTransfersViaACL(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	a := fake.api(pool)

	hh, owner, _ := seedCalHousehold(t, pool, "Handover ACL")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, owner, "owner@example.com")
	connectGoogle(t, pool, hh, partner, "partner@example.com")
	if _, err := pool.Exec(ctx, `update households set calendar_id = 'shared-cal',
		calendar_owner_member_id = $1 where id = $2`, owner, hh); err != nil {
		t.Fatal(err)
	}

	var tokenAliveDuringACL atomic.Bool
	fake.beforeACL = func(string) {
		var exists bool
		_ = pool.QueryRow(context.Background(),
			`select exists(select 1 from google_accounts where member_id = $1)`, owner).Scan(&exists)
		tokenAliveDuringACL.Store(exists)
	}

	m := &Membership{MemberID: owner, HouseholdID: hh, Household: "Handover ACL", PartnerID: partner}
	rec := httptest.NewRecorder()
	a.GoogleDisconnect(rec, calendarRequest(m, http.MethodPost, "/v1/google/disconnect", ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	var out struct {
		Transferred   bool   `json:"calendar_owner_transferred"`
		CalendarError string `json:"calendar_error"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if !out.Transferred || out.CalendarError != "" {
		t.Fatalf("response %+v", out)
	}
	if !tokenAliveDuringACL.Load() {
		t.Fatal("ordering violated: the leaving owner's token was gone before the ACL call")
	}
	if roles := fake.roles(); len(roles) == 0 || roles[0] != google.ACLRoleOwner {
		t.Fatalf("acl roles = %v, want owner first", roles)
	}
	calID, newOwner := readCalendarState(t, pool, hh)
	if calID != "shared-cal" || newOwner != partner {
		t.Fatalf("calendar=%s owner=%s, want shared-cal / partner", calID, newOwner)
	}
	if fake.calCreates.Load() != 0 {
		t.Fatal("an ACL handover must not recreate the calendar")
	}
	var stillConnected bool
	_ = pool.QueryRow(ctx, `select exists(select 1 from google_accounts where member_id = $1)`,
		owner).Scan(&stillConnected)
	if stillConnected {
		t.Fatal("the disconnecting member's token was not deleted")
	}
}

// Google refuses to move ownership over the API (the case the PRD flags as
// unknown): Even rebuilds the calendar under the remaining partner and
// re-publishes the open dated todos so their Google view keeps working.
func TestOwnerDisconnectFallsBackToRecreate(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	fake.refuseRoles[google.ACLRoleOwner] = true
	fake.refuseRoles[google.ACLRoleWriter] = true
	fake.newCalendars = []string{"partner-cal"}
	a := fake.api(pool)

	hh, owner, _ := seedCalHousehold(t, pool, "Handover Recreate")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, owner, "owner@example.com")
	connectGoogle(t, pool, hh, partner, "partner@example.com")
	if _, err := pool.Exec(ctx, `update households set calendar_id = 'old-cal',
		calendar_owner_member_id = $1 where id = $2`, owner, hh); err != nil {
		t.Fatal(err)
	}
	var taskID string
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence,
			due_on, google_event_id, calendar_sync_state)
		values ($1,'Bin day','chore',$2,1,'weekly', current_date + 3, 'old-evt', 'synced')
		returning id`, hh, partner).Scan(&taskID); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: owner, HouseholdID: hh, Household: "Handover Recreate", PartnerID: partner}
	rec := httptest.NewRecorder()
	a.GoogleDisconnect(rec, calendarRequest(m, http.MethodPost, "/v1/google/disconnect", ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	var out struct {
		Transferred bool `json:"calendar_owner_transferred"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if !out.Transferred {
		t.Fatalf("recreate fallback must still report a transfer: %s", rec.Body.String())
	}
	// Each role is attempted twice: patch an existing rule, then insert one.
	roles := fake.roles()
	if len(roles) == 0 || roles[0] != google.ACLRoleOwner {
		t.Fatalf("owner role must be tried first, got %v", roles)
	}
	sawWriter := false
	for _, r := range roles {
		if r == google.ACLRoleWriter {
			sawWriter = true
		}
	}
	if !sawWriter {
		t.Fatalf("writer role must be tried before recreating, got %v", roles)
	}
	calID, newOwner := readCalendarState(t, pool, hh)
	if calID != "partner-cal" || newOwner != partner {
		t.Fatalf("calendar=%s owner=%s, want partner-cal / partner", calID, newOwner)
	}
	var eventID, state string
	if err := pool.QueryRow(ctx,
		`select google_event_id, calendar_sync_state from tasks where id = $1`, taskID).
		Scan(&eventID, &state); err != nil {
		t.Fatal(err)
	}
	if eventID == "old-evt" || state != "synced" {
		t.Fatalf("todo not re-published: event=%s state=%s", eventID, state)
	}
	if fake.calDeletes.Load() != 1 {
		t.Fatalf("abandoned calendar deletes = %d, want 1 (best effort, dying token)", fake.calDeletes.Load())
	}
}

// A member who does not own the calendar disconnects: the household's calendar
// identity is untouched, and only their own reader grant is revoked.
func TestNonOwnerDisconnectLeavesCalendar(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	a := fake.api(pool)

	hh, owner, _ := seedCalHousehold(t, pool, "Non-owner Disconnect")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, owner, "owner@example.com")
	connectGoogle(t, pool, hh, partner, "partner@example.com")
	if _, err := pool.Exec(ctx, `update households set calendar_id = 'shared-cal',
		calendar_owner_member_id = $1 where id = $2`, owner, hh); err != nil {
		t.Fatal(err)
	}
	if err := a.markCalendarListed(ctx, partner, true); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: partner, HouseholdID: hh, Household: "Non-owner Disconnect", PartnerID: owner}
	rec := httptest.NewRecorder()
	a.GoogleDisconnect(rec, calendarRequest(m, http.MethodPost, "/v1/google/disconnect", ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	var out struct {
		Transferred bool `json:"calendar_owner_transferred"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if out.Transferred {
		t.Fatal("a non-owner disconnect transfers nothing")
	}
	calID, calOwner := readCalendarState(t, pool, hh)
	if calID != "shared-cal" || calOwner != owner {
		t.Fatalf("calendar=%s owner=%s — the household's calendar must be untouched", calID, calOwner)
	}
	if fake.calCreates.Load() != 0 || fake.eventInserts.Load() != 0 {
		t.Fatal("a non-owner disconnect must not touch Google's calendar contents")
	}
	if fake.aclDeletes.Load() != 1 {
		t.Fatalf("reader grant revokes = %d, want 1", fake.aclDeletes.Load())
	}
}

// The owner leaves and nobody else is connected: publishing pauses, the
// calendar id stays, and the next member to connect adopts it.
func TestOwnerDisconnectWithNoPartnerKeepsCalendar(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	fake.newCalendars = []string{"adopted-cal"}
	a := fake.api(pool)

	hh, owner, _ := seedCalHousehold(t, pool, "Solo Disconnect")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, owner, "owner@example.com")
	if _, err := pool.Exec(ctx, `update households set calendar_id = 'lonely-cal',
		calendar_owner_member_id = $1 where id = $2`, owner, hh); err != nil {
		t.Fatal(err)
	}

	m := &Membership{MemberID: owner, HouseholdID: hh, Household: "Solo Disconnect", PartnerID: partner}
	rec := httptest.NewRecorder()
	a.GoogleDisconnect(rec, calendarRequest(m, http.MethodPost, "/v1/google/disconnect", ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	calID, calOwner := readCalendarState(t, pool, hh)
	if calID != "lonely-cal" || calOwner != owner {
		t.Fatalf("calendar=%s owner=%s — it must survive the disconnect", calID, calOwner)
	}

	// The partner connects later: their first publish adopts the calendar
	// because Google would refuse their writes to one they do not own.
	connectGoogle(t, pool, hh, partner, "partner@example.com")
	due := time.Now().In(Amsterdam).AddDate(0, 0, 2)
	var taskID string
	if err := pool.QueryRow(ctx, `insert into tasks (household_id, title, section, owner_member_id, weight, recurrence, due_on)
		values ($1,'Water the plants','chore',$2,1,'none',$3) returning id`,
		hh, partner, due.Format("2006-01-02")).Scan(&taskID); err != nil {
		t.Fatal(err)
	}
	partnerM := &Membership{MemberID: partner, HouseholdID: hh, Household: "Solo Disconnect", PartnerID: owner}
	if msg := a.publishTaskToCalendar(ctx, partnerM, taskID, "Water the plants", "", nil, &due, "1_day"); msg != "" {
		t.Fatalf("adopting publish failed: %s", msg)
	}
	calID, calOwner = readCalendarState(t, pool, hh)
	if calID != "adopted-cal" || calOwner != partner {
		t.Fatalf("calendar=%s owner=%s, want adopted-cal / partner", calID, calOwner)
	}
}
