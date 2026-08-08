package api

// Disconnect empties the leaving member's inbox: every draft their mailbox
// produced and every processed-email verdict goes, while the partner's mailbox
// and the household's own work (todos already approved) stay.
// Runs only with EVEN_TESTDB (compose db), like the other integration suites.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// seedDraft inserts one draft attributed to a member's mailbox.
func seedDraft(t *testing.T, pool *pgxpool.Pool, hh, memberID, subject, status string) string {
	t.Helper()
	var id string
	if err := pool.QueryRow(context.Background(), `
		insert into drafts (household_id, from_label, subject, urgency, title,
			owner_member_id, created_by, source_member_id, status, gmail_message_id)
		values ($1,'Sender',$2,1,$2,$3,$3,$3,$4,$5)
		returning id`, hh, subject, memberID, status, "msg-"+subject).Scan(&id); err != nil {
		t.Fatal(err)
	}
	return id
}

func seedProcessedEmail(t *testing.T, pool *pgxpool.Pool, hh, memberID, messageID string) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), `
		insert into processed_emails (household_id, member_id, gmail_message_id, actionable)
		values ($1,$2,$3,false)`, hh, memberID, messageID); err != nil {
		t.Fatal(err)
	}
}

func countRows(t *testing.T, pool *pgxpool.Pool, query string, args ...any) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(), query, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// The whole point of the flush: a disconnected mailbox leaves nothing behind
// that can no longer be refreshed — but it is *only* that mailbox.
func TestDisconnectFlushesTheCallersMailboxOnly(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	a := fake.api(pool)

	hh, me, _ := seedCalHousehold(t, pool, "Flush Mine")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, me, "me@example.com")
	connectGoogle(t, pool, hh, partner, "partner@example.com")

	// Every status counts: a pending draft, one already approved into a todo,
	// and one dismissed. All three came from this mailbox.
	seedDraft(t, pool, hh, me, "Water bill", "pending")
	seedDraft(t, pool, hh, me, "Old newsletter", "dismissed")
	approved := seedDraft(t, pool, hh, me, "Dentist", "approved")
	var taskID string
	if err := pool.QueryRow(ctx, `
		insert into tasks (household_id, title, section, owner_member_id, weight, recurrence)
		values ($1,'Dentist','admin',$2,1,'none') returning id`, hh, me).Scan(&taskID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `update drafts set resulting_task_id = $1 where id = $2`,
		taskID, approved); err != nil {
		t.Fatal(err)
	}
	seedDraft(t, pool, hh, partner, "Partner insurance", "pending")
	seedProcessedEmail(t, pool, hh, me, "mine-1")
	seedProcessedEmail(t, pool, hh, me, "mine-2")
	seedProcessedEmail(t, pool, hh, partner, "theirs-1")

	m := &Membership{MemberID: me, HouseholdID: hh, Household: "Flush Mine", PartnerID: partner}
	rec := httptest.NewRecorder()
	a.GoogleDisconnect(rec, calendarRequest(m, http.MethodPost, "/v1/google/disconnect", ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	var out struct {
		DraftsRemoved int    `json:"drafts_removed"`
		FlushError    string `json:"flush_error"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if out.DraftsRemoved != 3 || out.FlushError != "" {
		t.Fatalf("response %+v — want 3 drafts removed, no flush error", out)
	}

	if n := countRows(t, pool,
		`select count(*) from drafts where source_member_id = $1`, me); n != 0 {
		t.Fatalf("%d of the caller's drafts survived — every status must go", n)
	}
	if n := countRows(t, pool,
		`select count(*) from drafts where source_member_id = $1`, partner); n != 1 {
		t.Fatalf("partner drafts = %d, want 1 — their mailbox is not the caller's", n)
	}
	if n := countRows(t, pool,
		`select count(*) from processed_emails where member_id = $1`, me); n != 0 {
		t.Fatalf("%d verdicts survived — a reconnect would skip that mail", n)
	}
	if n := countRows(t, pool,
		`select count(*) from processed_emails where member_id = $1`, partner); n != 1 {
		t.Fatalf("partner verdicts = %d, want 1", n)
	}
	if n := countRows(t, pool, `select count(*) from tasks where id = $1`, taskID); n != 1 {
		t.Fatal("an approved draft's todo is household work — it must survive the disconnect")
	}
}

// Ordering: the calendar handover needs the leaving member's token *and* runs
// before anything is erased. The flush is the last step.
func TestDisconnectFlushesAfterTheCalendarHandover(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	fake := newFakeGoogle(t)
	a := fake.api(pool)

	hh, owner, _ := seedCalHousehold(t, pool, "Flush After Handover")
	partner := seedPartner(t, pool, hh)
	connectGoogle(t, pool, hh, owner, "owner@example.com")
	connectGoogle(t, pool, hh, partner, "partner@example.com")
	if _, err := pool.Exec(ctx, `update households set calendar_id = 'shared-cal',
		calendar_owner_member_id = $1 where id = $2`, owner, hh); err != nil {
		t.Fatal(err)
	}
	seedDraft(t, pool, hh, owner, "Council tax", "pending")
	seedProcessedEmail(t, pool, hh, owner, "owner-1")

	type snapshot struct{ token, drafts, processed int }
	var atHandover snapshot
	fake.beforeACL = func(string) {
		atHandover = snapshot{
			token: countRows(t, pool,
				`select count(*) from google_accounts where member_id = $1`, owner),
			drafts: countRows(t, pool,
				`select count(*) from drafts where source_member_id = $1`, owner),
			processed: countRows(t, pool,
				`select count(*) from processed_emails where member_id = $1`, owner),
		}
	}

	m := &Membership{MemberID: owner, HouseholdID: hh, Household: "Flush After Handover", PartnerID: partner}
	rec := httptest.NewRecorder()
	a.GoogleDisconnect(rec, calendarRequest(m, http.MethodPost, "/v1/google/disconnect", ""))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	var out struct {
		Transferred   bool   `json:"calendar_owner_transferred"`
		CalendarError string `json:"calendar_error"`
		DraftsRemoved int    `json:"drafts_removed"`
	}
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if !out.Transferred || out.CalendarError != "" {
		t.Fatalf("handover response %+v", out)
	}
	if atHandover.token != 1 {
		t.Fatal("ordering violated: the token was gone before the handover")
	}
	if atHandover.drafts != 1 || atHandover.processed != 1 {
		t.Fatalf("ordering violated: the flush ran before the handover (%+v)", atHandover)
	}
	if out.DraftsRemoved != 1 {
		t.Fatalf("drafts_removed = %d, want 1", out.DraftsRemoved)
	}
	if n := countRows(t, pool,
		`select count(*) from drafts where source_member_id = $1`, owner); n != 0 {
		t.Fatal("the inbox was not flushed after the handover")
	}
	if calID, newOwner := readCalendarState(t, pool, hh); calID != "shared-cal" || newOwner != partner {
		t.Fatalf("calendar=%s owner=%s, want shared-cal / partner", calID, newOwner)
	}
}
