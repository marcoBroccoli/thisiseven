package api

// Live-inbox sync test: fake Gmail (30 unprocessed mails) + fake Claude whose
// calls are gated by the test, proving drafts land batch by batch while the
// job reports sync_running, and that has_more + processed_emails behave.
// Runs only with EVEN_TESTDB (compose db), like TestFullFlow.

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/claude"
	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
)

func TestLiveSyncBatches(t *testing.T) {
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

	// --- fake Google: oauth token + 30 listed messages + metadata ---
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 3600})
	})
	mux.HandleFunc("/gmail/v1/users/me/labels", func(w http.ResponseWriter, _ *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"labels": []any{}})
	})
	mux.HandleFunc("/gmail/v1/users/me/messages", func(w http.ResponseWriter, _ *http.Request) {
		var msgs []map[string]string
		for i := 1; i <= 30; i++ {
			msgs = append(msgs, map[string]string{"id": fmt.Sprintf("g%02d", i)})
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"messages": msgs})
	})
	mux.HandleFunc("/gmail/v1/users/me/messages/", func(w http.ResponseWriter, r *http.Request) {
		id := strings.TrimPrefix(r.URL.Path, "/gmail/v1/users/me/messages/")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id": id, "snippet": "please pay the amount before the weekend",
			"internalDate": fmt.Sprint(time.Now().UnixMilli()),
			"payload": map[string]any{"headers": []map[string]string{
				{"name": "From", "value": "Vattenfall <billing@vattenfall.nl>"},
				{"name": "Subject", "value": "Invoice " + id},
			}},
		})
	})
	fakeGoogle := httptest.NewServer(mux)
	defer fakeGoogle.Close()

	// --- fake Claude: every 2nd email actionable; calls gated by the test ---
	gate := make(chan struct{}, 3)
	claudeSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-gate // released one call at a time
		var req struct {
			Messages []struct {
				Content string `json:"content"`
			} `json:"messages"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		var payload struct {
			Emails []claude.EmailInput `json:"emails"`
		}
		_ = json.Unmarshal([]byte(req.Messages[0].Content), &payload)
		var verdicts []map[string]any
		for i, e := range payload.Emails {
			actionable := i%2 == 0
			v := map[string]any{
				"id": e.ID, "actionable": actionable, "title": "", "summary": "",
				"amount_cents": nil, "due_on": nil, "urgency": 1,
			}
			if actionable {
				v["title"] = "Pay the Vattenfall bill " + e.ID
				v["summary"] = "Invoice, €12.40, due soon"
				v["amount_cents"] = 1240
				v["urgency"] = 2
			}
			verdicts = append(verdicts, v)
		}
		text, _ := json.Marshal(map[string]any{"verdicts": verdicts})
		_ = json.NewEncoder(w).Encode(map[string]any{
			"content":     []map[string]string{{"type": "text", "text": string(text)}},
			"stop_reason": "end_turn",
		})
	}))
	defer claudeSrv.Close()

	app := &API{
		DB:     pool,
		Google: google.New("cid", "sec", "", fakeGoogle.URL, fakeGoogle.URL),
		Claude: claude.New("test-key", claudeSrv.URL, ""),
	}

	// Seed a household + member + google account directly.
	hh, member := newUUID(), newUUID()
	user := newUUID()
	if _, err := pool.Exec(ctx, `insert into households (id, name, invite_code) values ($1,'Sync Test',$2)`,
		hh, strings.ToUpper(newUUID()[:6])); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `insert into members (id, household_id, user_id, display_name, color) values ($1,$2,$3,'Tester','clay')`,
		member, hh, user); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `insert into weeks (household_id, week_index, started_on) values ($1,1,current_date)`, hh); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `insert into google_accounts (household_id, email, refresh_token, client_kind, connected_by)
		values ($1,'t@example.com','rt','desktop',$2)`, hh, member); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `delete from households where id = $1`, hh)
	})

	draftCount := func() int {
		var n int
		if err := pool.QueryRow(context.Background(),
			`select count(*) from drafts where household_id = $1`, hh).Scan(&n); err != nil {
			t.Fatal(err)
		}
		return n
	}

	if !app.claimSync(hh) {
		t.Fatal("claim failed")
	}
	if app.claimSync(hh) {
		t.Fatal("second claim should be refused while running")
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		syncCtx, cancel := context.WithTimeout(ctx, time.Minute)
		defer cancel()
		app.runSync(syncCtx, hh)
	}()

	// Release batch 1 (10 emails, 5 actionable) and watch the inbox fill
	// while the job is still running.
	gate <- struct{}{}
	deadline := time.Now().Add(15 * time.Second)
	for draftCount() < 5 && time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
	}
	if n := draftCount(); n != 5 {
		t.Fatalf("after batch 1: drafts = %d, want 5", n)
	}
	if job := app.jobSnapshot(hh); !job.Running || job.Classified != 10 || job.Created != 5 || !job.HasMore {
		t.Fatalf("mid-run job = %+v", job)
	}

	// Release the rest (batch 2: 10, batch 3: 5) and let it finish.
	gate <- struct{}{}
	gate <- struct{}{}
	select {
	case <-done:
	case <-time.After(30 * time.Second):
		t.Fatal("sync did not finish")
	}

	job := app.jobSnapshot(hh)
	if job.Running || job.Err != "" {
		t.Fatalf("final job = %+v", job)
	}
	if job.Scanned != 25 || job.Classified != 25 || !job.HasMore {
		t.Fatalf("final job counters = %+v (want scanned/classified 25, has_more)", job)
	}
	if n := draftCount(); n != 13 { // ceil(25/2) odd positions per batch: 5+5+3
		t.Fatalf("final drafts = %d, want 13", n)
	}
	var processed int
	if err := pool.QueryRow(ctx, `select count(*) from processed_emails where household_id = $1`, hh).Scan(&processed); err != nil {
		t.Fatal(err)
	}
	if processed != 25 {
		t.Fatalf("processed_emails = %d, want 25", processed)
	}

	// Even-voice rewrite + gmail id surface in the draft JSON.
	var title string
	var gmailID *string
	if err := pool.QueryRow(ctx, `
		select title, gmail_message_id from drafts where household_id = $1 order by created_at limit 1`,
		hh).Scan(&title, &gmailID); err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(title, "Pay the Vattenfall bill") {
		t.Fatalf("title not rewritten: %q", title)
	}
	if gmailID == nil || *gmailID == "" {
		t.Fatal("gmail_message_id missing")
	}

	// A second run takes the remaining 5 and clears has_more.
	if !app.claimSync(hh) {
		t.Fatal("re-claim after finish failed")
	}
	go func() { gate <- struct{}{} }()
	syncCtx, cancel := context.WithTimeout(ctx, time.Minute)
	defer cancel()
	app.runSync(syncCtx, hh)
	job = app.jobSnapshot(hh)
	if job.Running || job.HasMore || job.Scanned != 5 {
		t.Fatalf("second run job = %+v", job)
	}
	if processedNow := draftCount(); processedNow != 16 { // +3 actionable of 5
		t.Fatalf("drafts after second run = %d, want 16", processedNow)
	}
}
