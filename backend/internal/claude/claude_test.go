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
			{"id":"m1","actionable":true,"title":"Pay the Vattenfall energy bill","summary":"July invoice, €112.40, due Jul 25","amount_cents":11240,"due_on":"2026-07-25","urgency":2,"duplicate_of":null,"category":"bills","needs_reply":false,"suggested_reply":""},
			{"id":"m2","actionable":false,"title":"","summary":"","amount_cents":null,"due_on":null,"urgency":1,"duplicate_of":null,"category":"other","needs_reply":false,"suggested_reply":""}
		]}`)))
	}))
	defer srv.Close()

	c := New("test-key", srv.URL, "")
	verdicts, err := c.Classify(context.Background(), []EmailInput{
		{ID: "m1", From: "Vattenfall <x@v.nl>", Subject: "Your July energy bill", Snippet: "€112.40 due"},
		{ID: "m2", From: "News <n@x.com>", Subject: "Weekly digest"},
	}, nil, "2026-07-17")
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
	if verdicts[0].NeedsReply || verdicts[0].SuggestedReply != "" {
		t.Errorf("unexpected reply verdict = %+v", verdicts[0])
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
	if _, err := c.Classify(context.Background(), []EmailInput{{ID: "x"}}, nil, "2026-07-17"); err != nil {
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
	if _, err := c.Classify(context.Background(), []EmailInput{{ID: "x"}}, nil, "2026-07-17"); err == nil {
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

func TestClassifyDedupeWithinBatch(t *testing.T) {
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		w.Write([]byte(fakeResponse(t, `{"verdicts":[
			{"id":"new","actionable":true,"title":"Fix the failed Anthropic payment","summary":"Card declined, retry","amount_cents":null,"due_on":null,"urgency":3,"duplicate_of":null,"category":"bills"},
			{"id":"old","actionable":false,"title":"","summary":"","amount_cents":null,"due_on":null,"urgency":1,"duplicate_of":"new","category":"other"},
			{"id":"ex","actionable":false,"title":"","summary":"","amount_cents":null,"due_on":null,"urgency":1,"duplicate_of":"existing","category":"other"}
		]}`)))
	}))
	defer srv.Close()

	c := New("k", srv.URL, "")
	verdicts, err := c.Classify(context.Background(), []EmailInput{
		{ID: "new", Subject: "Payment failed"}, {ID: "old", Subject: "Payment failed reminder"},
		{ID: "ex", Subject: "ICS statement"},
	}, []string{"Review your ICS card statement"}, "2026-07-17")
	if err != nil {
		t.Fatal(err)
	}
	if verdicts[0].DuplicateOf != nil || !verdicts[0].Actionable || verdicts[0].Category != "bills" {
		t.Errorf("kept verdict = %+v", verdicts[0])
	}
	if verdicts[1].DuplicateOf == nil || *verdicts[1].DuplicateOf != "new" {
		t.Errorf("dupe verdict = %+v", verdicts[1])
	}
	if verdicts[2].DuplicateOf == nil || *verdicts[2].DuplicateOf != "existing" {
		t.Errorf("existing-dupe verdict = %+v", verdicts[2])
	}
	// existing_pending context must reach the model.
	var payload struct {
		ExistingPending []string `json:"existing_pending"`
	}
	msgs := gotBody["messages"].([]any)
	content := msgs[0].(map[string]any)["content"].(string)
	_ = json.Unmarshal([]byte(content), &payload)
	if len(payload.ExistingPending) != 1 {
		t.Errorf("existing_pending not sent: %+v", payload)
	}
}

func TestClassifyRetriesEchoedSubject(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := calls.Add(1)
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		content := body["messages"].([]any)[0].(map[string]any)["content"].(string)
		if n == 1 {
			// Echoes the raw subject → must trigger a corrective pass.
			w.Write([]byte(fakeResponse(t, `{"verdicts":[
				{"id":"m1","actionable":true,"title":"Billing Problem","summary":"","amount_cents":null,"due_on":null,"urgency":2,"duplicate_of":null,"category":"bills"}
			]}`)))
			return
		}
		var payload struct {
			Feedback string `json:"feedback"`
		}
		_ = json.Unmarshal([]byte(content), &payload)
		if payload.Feedback == "" {
			t.Errorf("retry call missing feedback")
		}
		w.Write([]byte(fakeResponse(t, `{"verdicts":[
			{"id":"m1","actionable":true,"title":"Sort out the Alpha Vantage billing problem","summary":"Card on file was declined","amount_cents":null,"due_on":null,"urgency":2,"duplicate_of":null,"category":"bills"}
		]}`)))
	}))
	defer srv.Close()

	c := New("k", srv.URL, "")
	verdicts, err := c.Classify(context.Background(), []EmailInput{
		{ID: "m1", Subject: "Billing Problem"},
	}, nil, "2026-07-17")
	if err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 2 {
		t.Fatalf("calls = %d, want 2 (echo retry)", calls.Load())
	}
	if verdicts[0].Title != "Sort out the Alpha Vantage billing problem" {
		t.Errorf("title not corrected: %q", verdicts[0].Title)
	}
}

func TestEchoesSubject(t *testing.T) {
	cases := []struct {
		title, subject string
		want           bool
	}{
		{"Billing Problem", "Billing Problem", true},
		{"billing problem!", "Billing Problem", true},
		{"Re: Billing Problem", "Billing Problem", true},
		{"Pay the Vattenfall energy bill", "Your July energy bill is ready", false},
		{"", "Subject", false},
	}
	for _, c := range cases {
		if got := EchoesSubject(c.title, c.subject); got != c.want {
			t.Errorf("EchoesSubject(%q, %q) = %v, want %v", c.title, c.subject, got, c.want)
		}
	}
}
