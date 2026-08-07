package api

import (
	"encoding/json"
	"testing"
	"time"
)

func TestHubBroadcastDeliversJSON(t *testing.T) {
	h := NewHub()
	c := &wsClient{send: make(chan []byte, 4)}
	h.subscribe("hh-1", c)

	h.Broadcast("hh-1", HouseholdInvalidate{
		Type:          "household.invalidate",
		Scopes:        []string{"summary"},
		Reason:        "task_toggled",
		ActorMemberID: "member-1",
	})

	select {
	case data := <-c.send:
		var msg HouseholdInvalidate
		if err := json.Unmarshal(data, &msg); err != nil {
			t.Fatal(err)
		}
		if msg.Type != "household.invalidate" || msg.Reason != "task_toggled" {
			t.Fatalf("unexpected message: %+v", msg)
		}
		if len(msg.Scopes) != 1 || msg.Scopes[0] != "summary" {
			t.Fatalf("scopes: %v", msg.Scopes)
		}
	case <-time.After(time.Second):
		t.Fatal("expected broadcast")
	}
}

func TestHubBroadcastDropsWhenBufferFull(t *testing.T) {
	h := NewHub()
	c := &wsClient{send: make(chan []byte, 1)}
	h.subscribe("hh-1", c)
	c.send <- []byte(`{"type":"fill"}`)

	// Must not block the caller.
	done := make(chan struct{})
	go func() {
		h.Broadcast("hh-1", HouseholdInvalidate{
			Type:   "household.invalidate",
			Scopes: []string{"summary"},
			Reason: "task_created",
		})
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("Broadcast blocked on full buffer")
	}
}

func TestInvalidateSummaryNoopsWithoutHub(t *testing.T) {
	a := &API{}
	a.invalidateSummary("hh", "task_toggled", "m1") // must not panic
}
