package api

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/gorilla/websocket"
)

var householdWSUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

const (
	wsWriteWait  = 10 * time.Second
	wsPongWait   = 60 * time.Second
	wsPingPeriod = (wsPongWait * 9) / 10
	wsSendBuf    = 16
)

// HouseholdWS upgrades to a long-lived household channel (GET /v1/ws/household).
func (a *API) HouseholdWS(w http.ResponseWriter, r *http.Request) {
	if a.Hub == nil {
		http.Error(w, "realtime unavailable", http.StatusServiceUnavailable)
		return
	}
	m := membership(r)
	conn, err := householdWSUpgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Warn("household ws upgrade", "err", err)
		return
	}
	client := &wsClient{conn: conn, send: make(chan []byte, wsSendBuf)}
	a.Hub.subscribe(m.HouseholdID, client)
	defer func() {
		a.Hub.unsubscribe(m.HouseholdID, client)
		_ = conn.Close()
	}()

	go a.writePump(client)
	a.readPump(client)
}

func (a *API) writePump(c *wsClient) {
	ticker := time.NewTicker(wsPingPeriod)
	defer ticker.Stop()
	for {
		select {
		case msg, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(wsWriteWait))
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(wsWriteWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (a *API) readPump(c *wsClient) {
	defer close(c.send)
	_ = c.conn.SetReadDeadline(time.Now().Add(wsPongWait))
	c.conn.SetPongHandler(func(string) error {
		return c.conn.SetReadDeadline(time.Now().Add(wsPongWait))
	})
	for {
		_, data, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		var envelope struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(data, &envelope); err != nil {
			continue
		}
		if envelope.Type == "ping" {
			pong, _ := json.Marshal(map[string]string{"type": "pong"})
			select {
			case c.send <- pong:
			default:
			}
		}
	}
}
