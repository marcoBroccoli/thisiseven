package api

// Leaving a household.
//
// A household is a pair, but a person is not: they may hold several, and any
// of them may end. Leaving is a *soft* departure — the member row stays so the
// history that references it keeps its shape (completions on closed weeks, the
// expenses they paid, the settlements between the two of them) — but the row
// is invisible everywhere the household's current people are listed, and the
// seat is free for someone else. Coming back revives the same row.
//
// Contract: docs/product/API.md → POST /v1/households/{id}/leave.

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// archivedEvent is a todo the departure archived that still has a Google
// Calendar event behind it.
type archivedEvent struct {
	taskID  string
	eventID string
}

// POST /v1/households/{id}/leave → {ok, household_deleted}
//
// Addressed by path, like the invite routes: the caller is walking out of one
// specific household, which is rarely the one the app is looking at.
func (a *API) LeaveHousehold(w http.ResponseWriter, r *http.Request) {
	m, ok := a.memberOfPath(w, r)
	if !ok {
		return
	}
	ctx := r.Context()

	// 1. Google, in the disconnect order: the shared calendar is handed over
	//    while the caller's refresh token still exists, the token is dropped,
	//    and only then is their mailbox flushed.
	if err := a.disconnectGoogleOnLeave(ctx, m); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not disconnect Google before leaving")
		return
	}

	var (
		deleted  bool
		archived []archivedEvent
	)
	err := pgx.BeginFunc(ctx, a.DB, func(tx pgx.Tx) error {
		deleted, archived = false, nil
		if err := lockHousehold(ctx, tx, m.HouseholdID); err != nil {
			return err
		}
		// 2. Their open work leaves with them. It stays as archived history
		//    rather than disappearing: the beam for past weeks must still add
		//    up.
		rows, err := tx.Query(ctx, `
			update tasks set archived_at = now()
			where household_id = $1 and owner_member_id = $2 and archived_at is null
			returning id, google_event_id`, m.HouseholdID, m.MemberID)
		if err != nil {
			return err
		}
		for rows.Next() {
			var it archivedEvent
			var eventID *string
			if err := rows.Scan(&it.taskID, &eventID); err != nil {
				rows.Close()
				return err
			}
			if eventID != nil && *eventID != "" {
				it.eventID = *eventID
				archived = append(archived, it)
			}
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		// 3. The seat empties.
		if _, err := tx.Exec(ctx,
			`update members set left_at = now() where id = $1 and left_at is null`,
			m.MemberID); err != nil {
			return err
		}
		// 4. Last one out turns off the lights: a household nobody lives in is
		//    not history worth keeping, and its invite code should stop working.
		var remaining int
		if err := tx.QueryRow(ctx,
			`select count(*) from members where household_id = $1 and left_at is null`,
			m.HouseholdID).Scan(&remaining); err != nil {
			return err
		}
		if remaining > 0 {
			return nil
		}
		deleted = true
		return purgeHousehold(ctx, tx, m.HouseholdID)
	})
	if err != nil {
		slog.Error("leave household", "household", m.HouseholdID, "member", m.MemberID, "err", err)
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not leave the household")
		return
	}

	if !deleted {
		// Their dated todos are archived here but still drawn on the shared
		// calendar; left there, the next calendar sync would import them back
		// as fresh todos for the remaining partner.
		a.removeArchivedCalendarEvents(ctx, m, archived)
		a.invalidateSummary(m.HouseholdID, "member_left", m.MemberID)
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"ok": true, "household_deleted": deleted})
}

// disconnectGoogleOnLeave runs the same sequence as POST /v1/google/disconnect
// for a caller who is walking out — leaving must never strand a mailbox
// connection or a calendar nobody can write. It is a no-op when the caller
// never connected Google. Only the token delete is fatal: a failed handover or
// flush is logged, the departure still happens.
func (a *API) disconnectGoogleOnLeave(ctx context.Context, m *Membership) error {
	if a.Google == nil {
		return nil
	}
	if _, err := a.googleAccountForMember(ctx, m.MemberID); err != nil {
		return nil // not connected (or unreadable) — nothing to hand over
	}
	if _, calendarError := a.handoverCalendarOnDisconnect(ctx, m); calendarError != "" {
		slog.Warn("leave: calendar handover", "household", m.HouseholdID, "member", m.MemberID)
	}
	if _, err := a.DB.Exec(ctx,
		`delete from google_accounts where member_id = $1`, m.MemberID); err != nil {
		return err
	}
	a.Google.Forget(m.MemberID)
	if _, flushError := a.flushMailboxForMember(ctx, m.MemberID); flushError != "" {
		slog.Warn("leave: mailbox flush", "member", m.MemberID, "msg", flushError)
	}
	return nil
}

// removeArchivedCalendarEvents takes the leaver's todos off the shared Google
// calendar. Best-effort per todo, and it runs with whatever token the
// household has left (the partner's, after the handover) — a stray event is a
// nuisance, a blocked departure is not.
func (a *API) removeArchivedCalendarEvents(ctx context.Context, m *Membership, items []archivedEvent) {
	if len(items) == 0 || a.Google == nil || !a.Google.Configured() {
		return
	}
	for _, it := range items {
		if err := a.deleteTaskCalendarEvent(ctx, m, it.eventID); err != nil {
			slog.Warn("leave: calendar event not removed", "task", it.taskID, "err", err)
			continue
		}
		if err := a.clearTaskCalendarMapping(ctx, it.taskID); err != nil {
			slog.Warn("leave: calendar mapping not cleared", "task", it.taskID, "err", err)
		}
	}
}

// purgeHousehold deletes an empty household and everything in it, inside the
// caller's transaction.
//
// `delete from households` alone does NOT work. The member rows go with the
// household, but completions, expenses, settlements, trades and appreciations
// reference members(id) with NO ACTION (history must not evaporate when a
// member row is touched), and Postgres does not order a cascade to satisfy
// them — an appreciation, which cascades from weeks rather than from
// households, is still standing when its author is deleted:
//
//	ERROR: update or delete on table "members" violates foreign key constraint
//	"appreciations_from_member_id_fkey"
//
// So the children go first, in dependency order, and the cascade is left with
// nothing to trip over.
func purgeHousehold(ctx context.Context, tx pgx.Tx, householdID string) error {
	stmts := []string{
		// Completions hang off tasks (cascade) but also off members (no action).
		`delete from recurring_completions
		 where task_id in (select id from tasks where household_id = $1)`,
		`delete from completions
		 where task_id in (select id from tasks where household_id = $1)`,
		`delete from trades where household_id = $1`,
		`delete from appreciations
		 where week_id in (select id from weeks where household_id = $1)`,
		`delete from drafts where household_id = $1`,
		`delete from expenses where household_id = $1`,
		`delete from settlements where household_id = $1`,
		`delete from tasks where household_id = $1`,
		`delete from processed_emails where household_id = $1`,
		`delete from google_accounts where household_id = $1`,
		`delete from household_invites where household_id = $1`,
		// The household points back at a member (calendar owner); let go first.
		`update households set calendar_owner_member_id = null where id = $1`,
		`delete from members where household_id = $1`,
		`delete from weeks where household_id = $1`,
		`delete from households where id = $1`,
	}
	for _, sql := range stmts {
		if _, err := tx.Exec(ctx, sql, householdID); err != nil {
			return err
		}
	}
	return nil
}
