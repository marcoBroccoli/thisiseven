package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// admin.settings is a staging area, not a live config channel: evend does not
// read this table. Every handler here says so in its response so the UI can
// keep repeating it, and so nobody flips a key expecting the app to change.
const settingsDisclaimer = "evend does not read admin.settings yet. Changing a value records intent and an audit row; wiring a key into the service is a deliberate backend change."

var settingKeyPattern = regexp.MustCompile(`^[a-z][a-z0-9_]{1,63}$`)

type settingRow struct {
	Key         string          `json:"key"`
	Value       json.RawMessage `json:"value"`
	Description *string         `json:"description"`
	UpdatedAt   string          `json:"updated_at"`
	UpdatedBy   *string         `json:"updated_by"`
}

func (a *API) ListSettings(w http.ResponseWriter, r *http.Request) {
	rows, err := a.DB.Query(r.Context(), `
		select key, value, description, updated_at, updated_by
		  from admin.settings order by key`)
	if err != nil {
		fail(w, "list settings", err)
		return
	}
	defer rows.Close()
	out := []settingRow{}
	for rows.Next() {
		var s settingRow
		var updated time.Time
		if err := rows.Scan(&s.Key, &s.Value, &s.Description, &updated, &s.UpdatedBy); err != nil {
			fail(w, "scan setting", err)
			return
		}
		s.UpdatedAt = updated.UTC().Format(time.RFC3339)
		out = append(out, s)
	}
	if err := rows.Err(); err != nil {
		fail(w, "iterate settings", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"rows": out, "notice": settingsDisclaimer})
}

type settingWrite struct {
	Key         string          `json:"key"`
	Value       json.RawMessage `json:"value"`
	Description *string         `json:"description"`
}

// UpsertSetting creates or replaces one key. The value must be valid JSON of
// any shape — a bare string, a number, an object — because the table is typed
// jsonb and the console should not invent a schema evend has not asked for.
func (a *API) UpsertSetting(w http.ResponseWriter, r *http.Request) {
	adm, _ := adminFrom(r.Context())
	var req settingWrite
	if !decodeJSON(w, r, &req) {
		return
	}
	// A key in the path wins; POST /settings carries it in the body instead.
	if k := chi.URLParam(r, "key"); k != "" {
		req.Key = k
	}
	req.Key = strings.TrimSpace(strings.ToLower(req.Key))
	if !settingKeyPattern.MatchString(req.Key) {
		writeErr(w, http.StatusBadRequest, "bad_key",
			"A key is lowercase letters, digits and underscores, 2–64 characters, starting with a letter.")
		return
	}
	if len(req.Value) == 0 || !json.Valid(req.Value) {
		writeErr(w, http.StatusBadRequest, "bad_value", "Value must be valid JSON.")
		return
	}

	var before *settingRow
	var existing settingRow
	var updated time.Time
	err := a.DB.QueryRow(r.Context(), `
		select key, value, description, updated_at, updated_by
		  from admin.settings where key = $1`, req.Key).
		Scan(&existing.Key, &existing.Value, &existing.Description, &updated, &existing.UpdatedBy)
	if err == nil {
		existing.UpdatedAt = updated.UTC().Format(time.RFC3339)
		before = &existing
	} else if !errors.Is(err, pgx.ErrNoRows) {
		fail(w, "load setting", err)
		return
	}

	if _, err := a.DB.Exec(r.Context(), `
		insert into admin.settings (key, value, description, updated_by, updated_at)
		values ($1, $2, $3, $4, now())
		on conflict (key) do update
		   set value = excluded.value,
		       description = coalesce(excluded.description, admin.settings.description),
		       updated_by = excluded.updated_by,
		       updated_at = now()`,
		req.Key, []byte(req.Value), req.Description, adm.Email); err != nil {
		fail(w, "save setting", err)
		return
	}

	action := "setting.create"
	if before != nil {
		action = "setting.update"
	}
	a.audit(r, auditEntry{
		Action: action, TargetType: "setting", TargetID: req.Key,
		Summary: "Set " + req.Key,
		Before:  before,
		After:   map[string]any{"key": req.Key, "value": json.RawMessage(req.Value)},
	})
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "key": req.Key, "notice": settingsDisclaimer})
}

func (a *API) DeleteSetting(w http.ResponseWriter, r *http.Request) {
	key := chi.URLParam(r, "key")
	var before settingRow
	var updated time.Time
	err := a.DB.QueryRow(r.Context(), `
		select key, value, description, updated_at, updated_by
		  from admin.settings where key = $1`, key).
		Scan(&before.Key, &before.Value, &before.Description, &updated, &before.UpdatedBy)
	if errors.Is(err, pgx.ErrNoRows) {
		writeErr(w, http.StatusNotFound, "not_found", "No setting with that key.")
		return
	}
	if err != nil {
		fail(w, "load setting", err)
		return
	}
	before.UpdatedAt = updated.UTC().Format(time.RFC3339)
	if _, err := a.DB.Exec(r.Context(), `delete from admin.settings where key = $1`, key); err != nil {
		fail(w, "delete setting", err)
		return
	}
	a.audit(r, auditEntry{
		Action: "setting.delete", TargetType: "setting", TargetID: key,
		Summary: "Deleted " + key, Before: before,
	})
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
