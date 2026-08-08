package api

// Multi-household. One household still holds at most two people, but a person
// may now hold several households — their own place and a partner's. The
// client says which one it is looking at with `X-Household-Id`; a client that
// says nothing (build 12 and earlier) keeps working and lands on the most
// recently joined one.
//
// Runs only with EVEN_TESTDB (a database named even_test), like TestFullFlow.

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/auth"
)

// hClient is the api_test client plus the active-household header, so one
// person can drive two households from the same token.
type hClient struct {
	t         *testing.T
	base      string
	token     string
	household string // X-Household-Id; empty = let the server pick
}

func (c *hClient) do(method, path string, body any) (int, map[string]any) {
	c.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req, _ := http.NewRequest(method, c.base+path, &buf)
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	if c.household != "" {
		req.Header.Set("X-Household-Id", c.household)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer resp.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out
}

// in returns the same caller pointed at another household.
func (c *hClient) in(householdID string) *hClient {
	return &hClient{t: c.t, base: c.base, token: c.token, household: householdID}
}

// seedUser gives the caller a GoTrue identity — invites are matched on the
// auth email, so the suite needs real auth.users rows. The address is claimed
// (any leftover from an interrupted run is dropped) so the test is rerunnable.
func seedUser(t *testing.T, pool *pgxpool.Pool, base, secret, email string) *hClient {
	t.Helper()
	userID := newUUID()
	if _, err := pool.Exec(context.Background(),
		`delete from auth.users where email = $1`, email); err != nil {
		t.Fatalf("clear auth user %s: %v", email, err)
	}
	if _, err := pool.Exec(context.Background(), `
		insert into auth.users (id, email, aud, role) values ($1, $2, 'authenticated', 'authenticated')`,
		userID, email); err != nil {
		t.Fatalf("seed auth user %s: %v", email, err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `delete from auth.users where id = $1`, userID)
	})
	return &hClient{t: t, base: base, token: mintToken(t, []byte(secret), userID)}
}

func householdList(t *testing.T, c *hClient) ([]map[string]any, []map[string]any) {
	t.Helper()
	code, body := c.do("GET", "/v1/households", nil)
	mustStatus(t, code, 200, "list households", body)
	var hs, ivs []map[string]any
	for _, h := range body["households"].([]any) {
		hs = append(hs, h.(map[string]any))
	}
	for _, i := range body["invites"].([]any) {
		ivs = append(ivs, i.(map[string]any))
	}
	return hs, ivs
}

func TestMultiHousehold(t *testing.T) {
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
	// deletes below still need the pool. `defer db.Close()` would close it
	// before any of them and leave the test database dirty.
	t.Cleanup(db.Close)

	srv := httptest.NewServer(Router(&API{DB: db}, auth.NewVerifier([]byte(secret)), "http://127.0.0.1:1"))
	defer srv.Close()

	ada := seedUser(t, db, srv.URL, secret, "ada.multi@example.com")
	umut := seedUser(t, db, srv.URL, secret, "umut.multi@example.com")
	zoe := seedUser(t, db, srv.URL, secret, "zoe.multi@example.com")

	// --- One person, two households ------------------------------------
	code, alpha := ada.do("POST", "/v1/households", map[string]any{
		"name": "Alpha Huis", "display_name": "Ada"})
	mustStatus(t, code, 201, "create alpha", alpha)
	alphaID := alpha["id"].(string)
	code, beta := ada.do("POST", "/v1/households", map[string]any{
		"name": "Beta Huis", "display_name": "Ada B"})
	mustStatus(t, code, 201, "create beta — a second household is legal now", beta)
	betaID := beta["id"].(string)
	t.Cleanup(func() {
		_, _ = db.Exec(context.Background(),
			`delete from households where id = any($1)`, []string{alphaID, betaID})
	})

	hs, ivs := householdList(t, ada)
	if len(hs) != 2 || len(ivs) != 0 {
		t.Fatalf("ada should hold two households and no invites: %v / %v", hs, ivs)
	}
	for _, h := range hs {
		if h["is_owner"] != true || h["member_count"] != float64(1) || h["my_member_id"] == nil {
			t.Fatalf("own solo household reads wrong: %v", h)
		}
		if h["invite_code"] == nil || h["pending_invite_email"] != nil {
			t.Fatalf("invite fields wrong on a fresh household: %v", h)
		}
	}

	// No header → the most recently joined household (build-12 back-compat).
	code, me := ada.do("GET", "/v1/me", nil)
	mustStatus(t, code, 200, "me without header", me)
	if me["household"].(map[string]any)["id"] != betaID {
		t.Fatalf("headerless caller should land on the newest household: %v", me["household"])
	}
	// Header → that household, whichever it is.
	code, me = ada.in(alphaID).do("GET", "/v1/me", nil)
	mustStatus(t, code, 200, "me with header", me)
	if me["household"].(map[string]any)["id"] != alphaID {
		t.Fatalf("X-Household-Id ignored: %v", me["household"])
	}
	adaAlphaID := me["member"].(map[string]any)["id"].(string)

	// Data routes follow the header: a todo written in Alpha is invisible in Beta.
	code, task := ada.in(alphaID).do("POST", "/v1/tasks", map[string]any{
		"title": "Alpha laundry", "section": "chore",
		"owner_member_id": adaAlphaID, "weight": 1, "recurrence": "weekly"})
	mustStatus(t, code, 201, "task in alpha", task)
	code, sum := ada.in(betaID).do("GET", "/v1/summary", nil)
	mustStatus(t, code, 200, "beta summary", sum)
	for _, sec := range sum["sections"].([]any) {
		if n := len(sec.(map[string]any)["tasks"].([]any)); n != 0 {
			t.Fatalf("beta must not see alpha's todos: %v", sum["sections"])
		}
	}
	// WebSocket clients cannot set headers — ?household_id= is the same switch.
	code, sum = ada.do("GET", "/v1/summary?household_id="+alphaID, nil)
	mustStatus(t, code, 200, "summary via query param", sum)
	found := false
	for _, sec := range sum["sections"].([]any) {
		for _, tt := range sec.(map[string]any)["tasks"].([]any) {
			if tt.(map[string]any)["id"] == task["id"] {
				found = true
			}
		}
	}
	if !found {
		t.Fatal("?household_id= should resolve the same household as the header")
	}

	// A household you are not in is 403, never someone else's data.
	code, body := umut.in(alphaID).do("GET", "/v1/summary", nil)
	mustStatus(t, code, 403, "outsider with header", body)
	if body["error"].(map[string]any)["code"] != "not_in_household" {
		t.Fatalf("wrong error code: %v", body["error"])
	}
	code, body = umut.do("GET", "/v1/summary", nil)
	mustStatus(t, code, 409, "no household at all is still no_household", body)

	// --- Email invites (recorded, never sent) ---------------------------
	code, body = ada.do("POST", "/v1/households/"+alphaID+"/invite",
		map[string]any{"email": "  UMUT.Multi@Example.com "})
	mustStatus(t, code, 201, "invite umut", body)
	if body["email"] != "umut.multi@example.com" {
		t.Fatalf("invite email should be normalized: %v", body["email"])
	}
	code, body = ada.do("POST", "/v1/households/"+alphaID+"/invite",
		map[string]any{"email": "someone.else@example.com"})
	mustStatus(t, code, 409, "second invite for one seat", body)
	if body["error"].(map[string]any)["code"] != "invite_pending" {
		t.Fatalf("wrong error code: %v", body["error"])
	}
	code, body = ada.do("POST", "/v1/households/"+betaID+"/invite",
		map[string]any{"email": "ada.multi@example.com"})
	mustStatus(t, code, 422, "self invite", body)
	code, body = ada.do("POST", "/v1/households/"+betaID+"/invite",
		map[string]any{"email": "not-an-email"})
	mustStatus(t, code, 400, "malformed email", body)
	// Only a member may hand out the seat.
	code, body = umut.do("POST", "/v1/households/"+betaID+"/invite",
		map[string]any{"email": "zoe.multi@example.com"})
	mustStatus(t, code, 403, "outsider invites", body)

	// The invitee sees it without belonging anywhere yet.
	hs, ivs = householdList(t, umut)
	if len(hs) != 0 || len(ivs) != 1 {
		t.Fatalf("umut should see one invite and no households: %v / %v", hs, ivs)
	}
	inv := ivs[0]
	if inv["household_id"] != alphaID || inv["household_name"] != "Alpha Huis" || inv["invited_by_name"] != "Ada" {
		t.Fatalf("invite payload: %v", inv)
	}
	// It is addressed to umut, so nobody else can take it.
	code, body = zoe.do("POST", "/v1/invites/"+inv["id"].(string)+"/accept",
		map[string]any{"display_name": "Zoe"})
	mustStatus(t, code, 404, "accepting someone else's invite", body)

	code, house := umut.do("POST", "/v1/invites/"+inv["id"].(string)+"/accept",
		map[string]any{"display_name": "Umut"})
	mustStatus(t, code, 200, "accept invite", house)
	members := house["members"].([]any)
	if len(members) != 2 {
		t.Fatalf("accepting should seat the second member: %v", members)
	}
	for _, mm := range members {
		m := mm.(map[string]any)
		if m["display_name"] == "Ada" && m["color"] != "#A6552F" {
			t.Fatalf("creator should stay terracotta: %v", m)
		}
		if m["display_name"] == "Umut" && m["color"] != "#37756D" {
			t.Fatalf("invitee should get the free pine: %v", m)
		}
	}
	code, body = umut.do("POST", "/v1/invites/"+inv["id"].(string)+"/accept",
		map[string]any{"display_name": "Umut"})
	mustStatus(t, code, 404, "accepting a spent invite", body)

	hs, ivs = householdList(t, umut)
	if len(hs) != 1 || hs[0]["id"] != alphaID || len(ivs) != 0 {
		t.Fatalf("umut should now hold alpha and hold no invites: %v / %v", hs, ivs)
	}
	if hs[0]["is_owner"] != false || hs[0]["member_count"] != float64(2) {
		t.Fatalf("joiner is not the owner of a full household: %v", hs[0])
	}
	// A third person cannot be invited into a full pair.
	code, body = ada.do("POST", "/v1/households/"+alphaID+"/invite",
		map[string]any{"email": "zoe.multi@example.com"})
	mustStatus(t, code, 409, "invite into a full household", body)
	if body["error"].(map[string]any)["code"] != "household_full" {
		t.Fatalf("wrong error code: %v", body["error"])
	}

	// --- Revoke and decline ---------------------------------------------
	code, body = ada.do("POST", "/v1/households/"+betaID+"/invite",
		map[string]any{"email": "zoe.multi@example.com"})
	mustStatus(t, code, 201, "invite zoe to beta", body)
	hs, _ = householdList(t, ada)
	for _, h := range hs {
		if h["id"] == betaID && h["pending_invite_email"] != "zoe.multi@example.com" {
			t.Fatalf("beta should advertise its outstanding invite: %v", h)
		}
	}
	code, body = ada.do("DELETE", "/v1/households/"+betaID+"/invite", nil)
	mustStatus(t, code, 200, "revoke", body)
	code, body = ada.do("DELETE", "/v1/households/"+betaID+"/invite", nil)
	mustStatus(t, code, 404, "revoke twice", body)
	if _, ivs = householdList(t, zoe); len(ivs) != 0 {
		t.Fatalf("a revoked invite must disappear: %v", ivs)
	}

	// The seat is free again, so a fresh invite is allowed.
	code, body = ada.do("POST", "/v1/households/"+betaID+"/invite",
		map[string]any{"email": "zoe.multi@example.com"})
	mustStatus(t, code, 201, "re-invite after revoke", body)
	_, ivs = householdList(t, zoe)
	if len(ivs) != 1 {
		t.Fatalf("zoe should see the new invite: %v", ivs)
	}
	code, body = zoe.do("POST", "/v1/invites/"+ivs[0]["id"].(string)+"/decline", nil)
	mustStatus(t, code, 200, "decline", body)
	if _, ivs = householdList(t, zoe); len(ivs) != 0 {
		t.Fatalf("a declined invite is gone: %v", ivs)
	}

	// --- The invite code still works ------------------------------------
	code, body = zoe.do("POST", "/v1/households/join", map[string]any{
		"invite_code": beta["invite_code"].(string), "display_name": "Zoe"})
	mustStatus(t, code, 200, "join by code", body)
	for _, mm := range body["members"].([]any) {
		m := mm.(map[string]any)
		if m["display_name"] == "Zoe" && m["color"] != "#37756D" {
			t.Fatalf("code joiner should be pine: %v", m)
		}
	}
	// Twice is not a way to two seats.
	code, body = zoe.do("POST", "/v1/households/join", map[string]any{
		"invite_code": beta["invite_code"].(string), "display_name": "Zoe"})
	mustStatus(t, code, 409, "join the same household twice", body)
	if body["error"].(map[string]any)["code"] != "already_in_household" {
		t.Fatalf("wrong error code: %v", body["error"])
	}
	code, body = umut.do("POST", "/v1/households/join", map[string]any{
		"invite_code": beta["invite_code"].(string), "display_name": "Umut"})
	mustStatus(t, code, 409, "third person by code", body)
	if body["error"].(map[string]any)["code"] != "household_full" {
		t.Fatalf("wrong error code: %v", body["error"])
	}

	// Umut now holds Alpha only; a headerless call still resolves it.
	code, me = umut.do("GET", "/v1/me", nil)
	mustStatus(t, code, 200, "umut me", me)
	if me["household"].(map[string]any)["id"] != alphaID {
		t.Fatalf("umut should resolve alpha: %v", me["household"])
	}
	code, body = umut.in(betaID).do("GET", "/v1/me", nil)
	mustStatus(t, code, 403, "umut pointing at beta", body)

	// Zoe holds Beta; the two households she and Ada share stay separate rows.
	hs, _ = householdList(t, zoe)
	if len(hs) != 1 || hs[0]["id"] != betaID || hs[0]["is_owner"] != false {
		t.Fatalf("zoe should hold beta as a joiner: %v", hs)
	}
	if !strings.EqualFold(hs[0]["name"].(string), "Beta Huis") {
		t.Fatalf("household name: %v", hs[0]["name"])
	}
}
