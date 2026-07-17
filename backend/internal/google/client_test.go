package google

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func fakeOAuth(t *testing.T, hits *atomic.Int32, refreshOK bool) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/token" {
			http.NotFound(w, r)
			return
		}
		hits.Add(1)
		_ = r.ParseForm()
		w.Header().Set("Content-Type", "application/json")
		switch r.Form.Get("grant_type") {
		case "authorization_code":
			payload, _ := json.Marshal(map[string]string{"email": "house@even.dev"})
			idToken := "h." + base64.RawURLEncoding.EncodeToString(payload) + ".s"
			_ = json.NewEncoder(w).Encode(map[string]any{
				"access_token": "at-1", "refresh_token": "rt-1",
				"expires_in": 3600, "id_token": idToken,
			})
		case "refresh_token":
			if !refreshOK {
				w.WriteHeader(http.StatusBadRequest)
				_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid_grant"})
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"access_token": "at-fresh", "expires_in": 3600,
			})
		default:
			w.WriteHeader(http.StatusBadRequest)
		}
	}))
}

func TestExchangeCodeParsesEmail(t *testing.T) {
	var hits atomic.Int32
	srv := fakeOAuth(t, &hits, true)
	defer srv.Close()
	c := New("id", "secret", srv.URL, "")
	refresh, email, err := c.ExchangeCode(context.Background(), "code", "http://127.0.0.1/cb", "")
	if err != nil {
		t.Fatal(err)
	}
	if refresh != "rt-1" || email != "house@even.dev" {
		t.Fatalf("got %q %q", refresh, email)
	}
}

func TestAccessTokenCachesPerHousehold(t *testing.T) {
	var hits atomic.Int32
	srv := fakeOAuth(t, &hits, true)
	defer srv.Close()
	c := New("id", "secret", srv.URL, "")
	for i := 0; i < 3; i++ {
		tok, err := c.AccessToken(context.Background(), "hh-1", "rt-1")
		if err != nil {
			t.Fatal(err)
		}
		if tok != "at-fresh" {
			t.Fatalf("token = %q", tok)
		}
	}
	if hits.Load() != 1 {
		t.Fatalf("token endpoint hit %d times, want 1 (cache)", hits.Load())
	}
}

func TestInvalidGrantSurfaces(t *testing.T) {
	var hits atomic.Int32
	srv := fakeOAuth(t, &hits, false)
	defer srv.Close()
	c := New("id", "secret", srv.URL, "")
	_, err := c.AccessToken(context.Background(), "hh-1", "rt-dead")
	if err != ErrInvalidGrant {
		t.Fatalf("err = %v, want ErrInvalidGrant", err)
	}
}

func TestNotConfigured(t *testing.T) {
	c := New("", "", "", "")
	if c.Configured() {
		t.Fatal("empty client should not be configured")
	}
	if _, _, err := c.ExchangeCode(context.Background(), "x", "y", ""); err != ErrNotConfigured {
		t.Fatalf("err = %v, want ErrNotConfigured", err)
	}
}

func TestGmailListAndMetaAndCalendarInsert(t *testing.T) {
	api := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.URL.Path == "/gmail/v1/users/me/labels":
			_, _ = w.Write([]byte(`{"labels":[{"id":"L1","name":"HouseholdTodo"}]}`))
		case r.URL.Path == "/gmail/v1/users/me/messages":
			if r.URL.Query().Get("labelIds") != "L1" {
				t.Errorf("expected label query, got %s", r.URL.RawQuery)
			}
			_, _ = w.Write([]byte(`{"messages":[{"id":"m1"}]}`))
		case r.URL.Path == "/gmail/v1/users/me/messages/m1":
			_, _ = w.Write([]byte(`{"id":"m1","snippet":"Amount: €12.50 due tomorrow",
				"internalDate":"1752750000000",
				"payload":{"headers":[{"name":"From","value":"Vattenfall <no@vf.nl>"},{"name":"Subject","value":"Bill"}]}}`))
		case r.URL.Path == "/calendar/v3/calendars/primary/events":
			_, _ = w.Write([]byte(`{"id":"ev1","htmlLink":"https://cal/ev1"}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer api.Close()
	c := New("id", "secret", "", api.URL)

	ids, err := c.ListHouseholdMessages(context.Background(), "tok", 25)
	if err != nil || len(ids) != 1 || ids[0] != "m1" {
		t.Fatalf("list: %v %v", ids, err)
	}
	m, err := c.MessageMeta(context.Background(), "tok", "m1")
	if err != nil || m.Subject != "Bill" || m.From != "Vattenfall <no@vf.nl>" {
		t.Fatalf("meta: %+v %v", m, err)
	}
	id, link, err := c.InsertEvent(context.Background(), "tok", "primary",
		BuildEvent("Bill", "VATTENFALL", nil, m.Date, "on_day"))
	if err != nil || id != "ev1" || link != "https://cal/ev1" {
		t.Fatalf("insert: %q %q %v", id, link, err)
	}
}
