package api

import (
	"encoding/json"
	"sync"

	"github.com/gorilla/websocket"
)

// Hub is an in-process fan-out for household WebSocket clients (single-node
// evend). Multi-replica would need an external pubsub.
type Hub struct {
	mu    sync.Mutex
	rooms map[string]map[*wsClient]struct{}
}

type wsClient struct {
	conn *websocket.Conn
	send chan []byte
}

func NewHub() *Hub {
	return &Hub{rooms: map[string]map[*wsClient]struct{}{}}
}

func (h *Hub) subscribe(householdID string, c *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	room := h.rooms[householdID]
	if room == nil {
		room = map[*wsClient]struct{}{}
		h.rooms[householdID] = room
	}
	room[c] = struct{}{}
}

func (h *Hub) unsubscribe(householdID string, c *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	room := h.rooms[householdID]
	if room == nil {
		return
	}
	delete(room, c)
	if len(room) == 0 {
		delete(h.rooms, householdID)
	}
}

// Broadcast JSON-encodes msg and non-blocking-sends to every subscriber in the
// household. Full buffers drop the frame (slow client) rather than blocking
// the HTTP mutation path.
func (h *Hub) Broadcast(householdID string, msg any) {
	if h == nil {
		return
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.rooms[householdID] {
		select {
		case c.send <- data:
		default:
			// Drop — client is behind.
		}
	}
}

// HouseholdInvalidate is the server → client envelope (API.md).
type HouseholdInvalidate struct {
	Type          string   `json:"type"`
	Scopes        []string `json:"scopes"`
	Reason        string   `json:"reason"`
	ActorMemberID string   `json:"actor_member_id"`
}

func (a *API) invalidateSummary(householdID, reason, actorMemberID string) {
	if a.Hub == nil {
		return
	}
	a.Hub.Broadcast(householdID, HouseholdInvalidate{
		Type:          "household.invalidate",
		Scopes:        []string{"summary"},
		Reason:        reason,
		ActorMemberID: actorMemberID,
	})
}
