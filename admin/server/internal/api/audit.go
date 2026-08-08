package api

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
)

type auditEntry struct {
	Action     string
	TargetType string
	TargetID   string
	Summary    string
	Before     any
	After      any
}

// audit records a completed write. It is called after the product write
// commits, never before: a log line for a change that did not happen is worse
// than no line at all, because it is believed.
//
// A failure to log is loud in the service log but does not fail the request —
// the change already happened, and returning 500 would tell the operator a lie.
func (a *API) audit(r *http.Request, e auditEntry) {
	adm, _ := adminFrom(r.Context())
	ctx := context.WithoutCancel(r.Context())
	beforeJSON := marshalState(e.Before)
	afterJSON := marshalState(e.After)
	var adminID *string
	if adm.ID != "" {
		adminID = &adm.ID
	}
	if _, err := a.DB.Exec(ctx, `
		insert into admin.audit_log
		  (admin_user_id, actor_email, action, target_type, target_id, summary,
		   before_json, after_json, ip)
		values ($1, $2, $3, nullif($4,''), nullif($5,''), nullif($6,''), $7, $8, $9)`,
		adminID, adm.Email, e.Action, e.TargetType, e.TargetID, e.Summary,
		beforeJSON, afterJSON, clientIP(r)); err != nil {
		slog.Error("AUDIT WRITE FAILED", "action", e.Action, "target", e.TargetID, "err", err)
	}
}

// marshalState renders a before/after payload, or nil when there is genuinely
// no state to record.
//
// The nil check has to happen on the *marshalled* value, not the interface. A
// handler that reads "no previous row" into a `*settingRow` and passes that
// typed nil into an `any` field produces a non-nil interface holding a nil
// pointer — so `e.Before != nil` is true and the column would store jsonb
// 'null'. That is not SQL NULL, and it makes a create indistinguishable from an
// update that blanked the row. Both are lies in a log whose whole job is to be
// trusted after the fact.
func marshalState(v any) []byte {
	if v == nil {
		return nil
	}
	raw, err := json.Marshal(v)
	if err != nil || string(raw) == "null" {
		return nil
	}
	return raw
}

type auditRow struct {
	ID         int64            `json:"id"`
	ActorEmail string           `json:"actor_email"`
	Action     string           `json:"action"`
	TargetType *string          `json:"target_type"`
	TargetID   *string          `json:"target_id"`
	Summary    *string          `json:"summary"`
	Before     *json.RawMessage `json:"before"`
	After      *json.RawMessage `json:"after"`
	IP         *string          `json:"ip"`
	CreatedAt  string           `json:"created_at"`
}

// ListAudit is the audit trail page: newest first, searchable across actor,
// action and target.
func (a *API) ListAudit(w http.ResponseWriter, r *http.Request) {
	p := readPage(r)
	action := r.URL.Query().Get("action")

	var total int
	if err := a.DB.QueryRow(r.Context(), `
		select count(*) from admin.audit_log
		 where ($1 = '%' or actor_email ilike $1 or action ilike $1 or coalesce(target_id,'') ilike $1)
		   and ($2 = '' or action = $2)`, p.like(), action).Scan(&total); err != nil {
		fail(w, "count audit", err)
		return
	}
	rows, err := a.DB.Query(r.Context(), `
		select id, actor_email, action, target_type, target_id, summary,
		       before_json, after_json, ip, created_at
		  from admin.audit_log
		 where ($1 = '%' or actor_email ilike $1 or action ilike $1 or coalesce(target_id,'') ilike $1)
		   and ($2 = '' or action = $2)
		 order by created_at desc, id desc
		 limit $3 offset $4`, p.like(), action, p.Limit, p.Offset)
	if err != nil {
		fail(w, "list audit", err)
		return
	}
	defer rows.Close()

	out := []auditRow{}
	for rows.Next() {
		var e auditRow
		var created any
		if err := rows.Scan(&e.ID, &e.ActorEmail, &e.Action, &e.TargetType, &e.TargetID,
			&e.Summary, &e.Before, &e.After, &e.IP, &created); err != nil {
			fail(w, "scan audit", err)
			return
		}
		e.CreatedAt = rfc3339(created)
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		fail(w, "iterate audit", err)
		return
	}

	actions, err := a.distinct(r.Context(), `select distinct action from admin.audit_log order by 1`)
	if err != nil {
		fail(w, "audit actions", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"rows": out, "page": p.meta(total), "actions": actions,
	})
}

func (a *API) distinct(ctx context.Context, query string) ([]string, error) {
	rows, err := a.DB.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var s string
		if err := rows.Scan(&s); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
