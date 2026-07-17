package api

// Integration suite: runs only when EVEN_TESTDB is set, against the compose
// Postgres (127.0.0.1:5433 from the host, db:5432 inside the network).
// The evend container has already applied migrations by the time this runs.
//
//   EVEN_TESTDB=postgres://even:PW@127.0.0.1:5433/even?sslmode=disable \
//   EVEN_GOTRUE_JWT_SECRET=… go test ./internal/api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"crypto/rand"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/auth"
)

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

type client struct {
	t     *testing.T
	base  string
	token string
}

func (c *client) do(method, path string, body any) (int, map[string]any) {
	c.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req, _ := http.NewRequest(method, c.base+path, &buf)
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

func (c *client) doList(method, path string, body any) (int, []map[string]any) {
	c.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req, _ := http.NewRequest(method, c.base+path, &buf)
	req.Header.Set("Authorization", "Bearer "+c.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer resp.Body.Close()
	var out []map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

func mustStatus(t *testing.T, got, want int, ctx string, body any) {
	t.Helper()
	if got != want {
		t.Fatalf("%s: status %d, want %d — %v", ctx, got, want, body)
	}
}

func mintToken(t *testing.T, secret []byte, sub string) string {
	t.Helper()
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": sub, "aud": "authenticated",
		"exp": time.Now().Add(time.Hour).Unix(),
	})
	s, err := tok.SignedString(secret)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestFullFlow(t *testing.T) {
	dbURL := os.Getenv("EVEN_TESTDB")
	if dbURL == "" {
		t.Skip("EVEN_TESTDB not set")
	}
	secret := []byte(os.Getenv("EVEN_GOTRUE_JWT_SECRET"))
	if len(secret) == 0 {
		t.Fatal("EVEN_GOTRUE_JWT_SECRET required")
	}

	db, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	srv := httptest.NewServer(Router(&API{DB: db}, auth.NewVerifier(secret), "http://127.0.0.1:1"))
	defer srv.Close()

	ada := &client{t: t, base: srv.URL, token: mintToken(t, secret, newUUID())}
	umut := &client{t: t, base: srv.URL, token: mintToken(t, secret, newUUID())}
	third := &client{t: t, base: srv.URL, token: mintToken(t, secret, newUUID())}

	// Unauthenticated → 401.
	anon := &client{t: t, base: srv.URL, token: "garbage"}
	code, body := anon.do("GET", "/v1/me", nil)
	mustStatus(t, code, 401, "anon me", body)

	// Pre-onboarding: /v1/me has null member; data routes 409.
	code, body = ada.do("GET", "/v1/me", nil)
	mustStatus(t, code, 200, "me", body)
	if body["member"] != nil {
		t.Fatal("expected null member before onboarding")
	}
	code, body = ada.do("GET", "/v1/summary", nil)
	mustStatus(t, code, 409, "summary pre-household", body)

	// Create + join.
	code, house := ada.do("POST", "/v1/households", map[string]any{
		"name": "Test Huis", "display_name": "Ada"})
	mustStatus(t, code, 201, "create household", house)
	invite := house["invite_code"].(string)
	members := house["members"].([]any)
	if len(members) != 1 || members[0].(map[string]any)["color"] != "clay" {
		t.Fatalf("creator should be clay: %v", members)
	}

	code, body = umut.do("POST", "/v1/households/join", map[string]any{
		"invite_code": invite, "display_name": "Umut"})
	mustStatus(t, code, 200, "join", body)
	var adaID, umutID string
	for _, mm := range body["members"].([]any) {
		m := mm.(map[string]any)
		if m["display_name"] == "Ada" {
			adaID = m["id"].(string)
		} else {
			umutID = m["id"].(string)
			if m["color"] != "teal" {
				t.Fatalf("joiner should be teal: %v", m)
			}
		}
	}

	code, body = third.do("POST", "/v1/households/join", map[string]any{
		"invite_code": invite, "display_name": "Nope"})
	mustStatus(t, code, 409, "third join", body)

	// Tasks + summary math.
	code, task := ada.do("POST", "/v1/tasks", map[string]any{
		"title": "Laundry — towels", "section": "chore",
		"owner_member_id": adaID, "weight": 2, "recurrence": "weekly"})
	mustStatus(t, code, 201, "create task", task)
	taskID := task["id"].(string)

	code, task2 := ada.do("POST", "/v1/tasks", map[string]any{
		"title": "Dishes tonight", "section": "chore",
		"owner_member_id": umutID, "weight": 1, "recurrence": "daily"})
	mustStatus(t, code, 201, "create task2", task2)
	task2ID := task2["id"].(string)

	code, body = ada.do("POST", "/v1/tasks/"+taskID+"/toggle", nil)
	mustStatus(t, code, 200, "toggle", body)
	if body["done"] != true {
		t.Fatal("task should be done")
	}
	code, body = umut.do("POST", "/v1/tasks/"+task2ID+"/toggle", nil)
	mustStatus(t, code, 200, "toggle2", body)

	code, sum := ada.do("GET", "/v1/summary", nil)
	mustStatus(t, code, 200, "summary", sum)
	// Ada 2 of 3 → 67 / 33.
	if int(sum["percent_me"].(float64)) != 67 || int(sum["percent_partner"].(float64)) != 33 {
		t.Fatalf("summary pct: %v/%v", sum["percent_me"], sum["percent_partner"])
	}
	if n := len(sum["pebbles"].([]any)); n != 2 {
		t.Fatalf("want 2 pebbles, got %d", n)
	}

	// Toggle off removes the pebble.
	code, body = umut.do("POST", "/v1/tasks/"+task2ID+"/toggle", nil)
	mustStatus(t, code, 200, "untoggle", body)
	if body["done"] != false {
		t.Fatal("task2 should be undone")
	}
	code, sum = ada.do("GET", "/v1/summary", nil)
	mustStatus(t, code, 200, "summary2", sum)
	if int(sum["percent_me"].(float64)) != 100 {
		t.Fatalf("solo pebble should read 100, got %v", sum["percent_me"])
	}

	// Drafts.
	code, draft := umut.do("POST", "/v1/drafts", map[string]any{
		"from_label": "Vattenfall", "subject": "July energy bill",
		"urgency": 2, "amount_cents": 11240, "due_on": "2026-07-25",
		"owner_member_id": umutID})
	mustStatus(t, code, 201, "draft", draft)
	draftID := draft["id"].(string)

	code, body = ada.do("PATCH", "/v1/drafts/"+draftID, map[string]any{
		"title": "Pay Vattenfall — July", "reminder": "1_day"})
	mustStatus(t, code, 200, "draft patch", body)
	if body["title"] != "Pay Vattenfall — July" {
		t.Fatalf("draft title: %v", body["title"])
	}

	code, appr := ada.do("POST", "/v1/drafts/"+draftID+"/approve", nil)
	mustStatus(t, code, 200, "approve", appr)
	newTask := appr["task"].(map[string]any)
	if newTask["section"] != "admin" || newTask["owner_member_id"] != umutID {
		t.Fatalf("approved task wrong: %v", newTask)
	}
	code, drafts := ada.doList("GET", "/v1/drafts?status=pending", nil)
	mustStatus(t, code, 200, "drafts pending", drafts)
	if len(drafts) != 0 {
		t.Fatalf("pending should be empty, got %d", len(drafts))
	}

	// Money.
	code, money := ada.do("POST", "/v1/expenses", map[string]any{
		"title": "Groceries", "amount_cents": 8620, "paid_by_member_id": adaID,
		"incurred_on": time.Now().UTC().Format("2006-01-02")})
	mustStatus(t, code, 201, "expense", money)
	code, money = umut.do("POST", "/v1/expenses", map[string]any{
		"title": "Internet", "amount_cents": 3999, "paid_by_member_id": umutID})
	mustStatus(t, code, 201, "expense2", money)
	// (8620-3999)/2 = 2310.5 → 2311, Umut owes Ada.
	if int64(money["balance_cents"].(float64)) != 2311 {
		t.Fatalf("balance: %v", money["balance_cents"])
	}
	if *jstr(money, "debtor_member_id") != umutID {
		t.Fatalf("debtor: %v", money["debtor_member_id"])
	}

	code, money = umut.do("POST", "/v1/settle", nil)
	mustStatus(t, code, 200, "settle", money)
	if int64(money["balance_cents"].(float64)) != 0 {
		t.Fatalf("post-settle balance: %v", money["balance_cents"])
	}
	code, body = umut.do("POST", "/v1/settle", nil)
	mustStatus(t, code, 409, "double settle", body)

	// Reset: appreciation + trade + close.
	code, body = ada.do("PUT", "/v1/appreciations/mine", map[string]any{
		"body": "You cleared the inbox. Noticed.", "said": true})
	mustStatus(t, code, 200, "appreciation", body)

	code, trade := ada.do("POST", "/v1/trades", map[string]any{"task_id": taskID})
	mustStatus(t, code, 201, "trade", trade)
	tradeID := trade["id"].(string)
	code, body = ada.do("POST", "/v1/trades/"+tradeID+"/accept", map[string]any{"accepted": true})
	mustStatus(t, code, 409, "self accept", body)
	code, body = umut.do("POST", "/v1/trades/"+tradeID+"/accept", map[string]any{"accepted": true})
	mustStatus(t, code, 200, "accept", body)

	code, reset := ada.do("GET", "/v1/reset", nil)
	mustStatus(t, code, 200, "reset", reset)
	if reset["biggest_carry"] == "" {
		t.Fatal("biggest_carry empty")
	}
	weekID := reset["week"].(map[string]any)["id"].(string)

	code, closeOut := ada.do("POST", "/v1/week/close", map[string]any{"week_id": weekID})
	mustStatus(t, code, 200, "close", closeOut)
	if closeOut["new_week"].(map[string]any)["index"].(float64) != 2 {
		t.Fatalf("new week index: %v", closeOut["new_week"])
	}
	// Stale week id → guarded.
	code, body = ada.do("POST", "/v1/week/close", map[string]any{"week_id": weekID})
	mustStatus(t, code, 409, "double close", body)

	// After the pour: pans empty, weekly task traded to Umut, still present.
	code, sum = ada.do("GET", "/v1/summary", nil)
	mustStatus(t, code, 200, "summary after close", sum)
	if len(sum["pebbles"].([]any)) != 0 {
		t.Fatal("pans should be empty after close")
	}
	found := false
	for _, sec := range sum["sections"].([]any) {
		for _, tt := range sec.(map[string]any)["tasks"].([]any) {
			task := tt.(map[string]any)
			if task["id"] == taskID {
				found = true
				if task["owner_member_id"] != umutID {
					t.Fatalf("trade not applied: %v", task["owner_member_id"])
				}
				if task["done"] != false {
					t.Fatal("recurring task should reset to undone")
				}
			}
			if task["id"] == newTask["id"] && newTask["done"] == true {
				t.Fatal("finished one-off admin task should be archived")
			}
		}
	}
	if !found {
		t.Fatal("weekly task should survive the close")
	}
	fmt.Println("full flow ok")
}

func jstr(m map[string]any, k string) *string {
	if v, ok := m[k].(string); ok {
		return &v
	}
	return nil
}
