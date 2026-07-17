package claude

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func fakeResponse(t *testing.T, verdicts string) string {
	t.Helper()
	body, _ := json.Marshal(map[string]any{
		"content":     []map[string]string{{"type": "text", "text": verdicts}},
		"stop_reason": "end_turn",
	})
	return string(body)
}

func TestClassifyParsesVerdicts(t *testing.T) {
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" {
			t.Errorf("path = %s", r.URL.Path)
		}
		if r.Header.Get("x-api-key") != "test-key" {
			t.Errorf("missing api key header")
		}
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		w.Write([]byte(fakeResponse(t, `{"verdicts":[
			{"id":"m1","actionable":true,"title":"Pay the Vattenfall energy bill","summary":"July invoice, €112.40, due Jul 25","amount_cents":11240,"due_on":"2026-07-25","urgency":2},
			{"id":"m2","actionable":false,"title":"","summary":"","amount_cents":null,"due_on":null,"urgency":1}
		]}`)))
	}))
	defer srv.Close()

	c := New("test-key", srv.URL, "")
	verdicts, err := c.Classify(context.Background(), []EmailInput{
		{ID: "m1", From: "Vattenfall <x@v.nl>", Subject: "Your July energy bill", Snippet: "€112.40 due"},
		{ID: "m2", From: "News <n@x.com>", Subject: "Weekly digest"},
	}, "2026-07-17")
	if err != nil {
		t.Fatal(err)
	}
	if len(verdicts) != 2 {
		t.Fatalf("verdicts = %d", len(verdicts))
	}
	if !verdicts[0].Actionable || verdicts[0].Title != "Pay the Vattenfall energy bill" ||
		verdicts[0].AmountCents == nil || *verdicts[0].AmountCents != 11240 {
		t.Errorf("verdict 0 = %+v", verdicts[0])
	}
	if verdicts[1].Actionable {
		t.Errorf("verdict 1 should be non-actionable")
	}
	if gotBody["model"] != defaultModel {
		t.Errorf("model = %v", gotBody["model"])
	}
	if _, ok := gotBody["output_config"].(map[string]any); !ok {
		t.Errorf("output_config missing")
	}
}

func TestClassifyRetriesOn500(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) == 1 {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.Write([]byte(fakeResponse(t, `{"verdicts":[]}`)))
	}))
	defer srv.Close()

	c := New("k", srv.URL, "")
	if _, err := c.Classify(context.Background(), []EmailInput{{ID: "x"}}, "2026-07-17"); err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 2 {
		t.Errorf("calls = %d, want 2", calls.Load())
	}
}

func TestClassifyDoesNotRetryOn400(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":{"message":"bad"}}`))
	}))
	defer srv.Close()

	c := New("k", srv.URL, "")
	if _, err := c.Classify(context.Background(), []EmailInput{{ID: "x"}}, "2026-07-17"); err == nil {
		t.Fatal("want error")
	}
	if calls.Load() != 1 {
		t.Errorf("calls = %d, want 1", calls.Load())
	}
}

func TestUnconfigured(t *testing.T) {
	c := New("", "", "")
	if c.Configured() {
		t.Fatal("empty key should not be configured")
	}
}
