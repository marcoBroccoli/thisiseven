package api

// The shared household calendar as a *mirror*: Even owns the todos, Google is
// a viewing surface for both partners. A Google secondary calendar has exactly
// one owning account, so Even records which member that is
// (households.calendar_owner_member_id), grants the partner **reader** access,
// and hands ownership over before the owning member's token is deleted.
//
// Contract: docs/product/API.md → Google / Calendar.

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// calendarState is the household's shared-calendar identity.
type calendarState struct {
	CalendarID    string
	OwnerMemberID string // "" when no calendar has been created yet
	LastSyncAt    *time.Time
}

// ready reports a real secondary calendar. "primary" is the pre-2026 default
// and must never be written to — it is somebody's personal calendar.
func (s calendarState) ready() bool {
	return s.CalendarID != "" && s.CalendarID != "primary"
}

func (a *API) calendarState(ctx context.Context, householdID string) (calendarState, error) {
	var s calendarState
	var owner *string
	err := a.DB.QueryRow(ctx, `
		select calendar_id, calendar_owner_member_id, calendar_last_sync_at
		from households where id = $1`, householdID).
		Scan(&s.CalendarID, &owner, &s.LastSyncAt)
	if owner != nil {
		s.OwnerMemberID = *owner
	}
	return s, err
}

// calendarWriteAccount picks the token Even writes the shared calendar with.
// Under mirror rules the partner is a *reader*, so the owner's token is the
// only one Google accepts writes from; the caller's own connection is merely
// the fallback used before an owner exists (or after they disconnected, where
// the caller then adopts the calendar).
func (a *API) calendarWriteAccount(ctx context.Context, m *Membership) (*googleAccount, error) {
	accounts, err := a.householdGoogleAccounts(ctx, m.HouseholdID)
	if err != nil {
		return nil, err
	}
	if len(accounts) == 0 {
		return nil, pgx.ErrNoRows
	}
	state, err := a.calendarState(ctx, m.HouseholdID)
	if err != nil {
		return nil, err
	}
	if state.OwnerMemberID != "" {
		for _, g := range accounts {
			if g.MemberID == state.OwnerMemberID {
				return g, nil
			}
		}
	}
	for _, g := range accounts {
		if g.MemberID == m.MemberID {
			return g, nil
		}
	}
	return accounts[0], nil
}

// setCalendarOwner records who owns the shared calendar. Called on create and
// on every handover — Even must never guess this from token order again.
func (a *API) setCalendarOwner(ctx context.Context, householdID, calendarID, memberID string) error {
	if _, err := a.DB.Exec(ctx, `
		update households set calendar_id = $1, calendar_owner_member_id = $2
		where id = $3`, calendarID, memberID, householdID); err != nil {
		return err
	}
	// The owner always sees their own calendar; nothing to "add".
	return a.markCalendarListed(ctx, memberID, true)
}

func (a *API) markCalendarListed(ctx context.Context, memberID string, listed bool) error {
	if listed {
		_, err := a.DB.Exec(ctx,
			`update google_accounts set calendar_listed_at = now() where member_id = $1`, memberID)
		return err
	}
	_, err := a.DB.Exec(ctx,
		`update google_accounts set calendar_listed_at = null where member_id = $1`, memberID)
	return err
}

func (a *API) calendarListedFor(ctx context.Context, memberID string) bool {
	var at *time.Time
	if err := a.DB.QueryRow(ctx,
		`select calendar_listed_at from google_accounts where member_id = $1`, memberID).Scan(&at); err != nil {
		return false
	}
	return at != nil
}

// ---- create / adopt ------------------------------------------------------

// ensureCalendarForWriter returns the calendar id `writer` may actually write:
//
//   - no calendar yet → create it under the writer, who becomes the owner;
//   - writer owns it → use it;
//   - somebody else owns it and that owner is the writer's fallback (their
//     Google connection is gone) → adopt: recreate under the writer and move
//     the open dated todos across, because Google will not let a non-owner
//     write a calendar they only read.
func (a *API) ensureCalendarForWriter(ctx context.Context, m *Membership,
	writer *googleAccount, token string, state calendarState) (string, error) {
	if !state.ready() {
		id, err := a.Google.CreateCalendar(ctx, token, "Even — "+m.Household)
		if err != nil {
			return "", err
		}
		if err := a.setCalendarOwner(ctx, m.HouseholdID, id, writer.MemberID); err != nil {
			return "", err
		}
		return id, nil
	}
	if state.OwnerMemberID == writer.MemberID {
		return state.CalendarID, nil
	}
	if state.OwnerMemberID == "" {
		// A calendar from before 013 whose owner could not be backfilled.
		// Claim it for the connected writer rather than abandoning a working
		// calendar: that is the same assumption the backfill makes, and if
		// Google disagrees the write fails loudly (retry_required).
		if err := a.setCalendarOwner(ctx, m.HouseholdID, state.CalendarID, writer.MemberID); err != nil {
			return "", err
		}
		return state.CalendarID, nil
	}
	// An owner is recorded but has no connection left. The writer cannot
	// publish into a calendar they only read, so they take it over.
	newID, err := a.recreateCalendarUnder(ctx, m.HouseholdID, m.Household, writer, token, state)
	if err != nil {
		return "", err
	}
	return newID, nil
}

// recreateCalendarUnder is the documented fallback for a handover Google will
// not perform over ACL: a fresh secondary calendar on the remaining account,
// with every open dated todo re-published so the partner's Google view keeps
// showing the household's schedule. The abandoned calendar is left alone (the
// caller may best-effort delete it while the dying token still works).
func (a *API) recreateCalendarUnder(ctx context.Context, householdID, householdName string,
	to *googleAccount, toToken string, state calendarState) (string, error) {
	newID, err := a.Google.CreateCalendar(ctx, toToken, "Even — "+householdName)
	if err != nil {
		return "", err
	}
	if _, err := a.DB.Exec(ctx, `
		update households set calendar_id = $1, calendar_owner_member_id = $2,
			calendar_last_sync_at = null
		where id = $3`, newID, to.MemberID, householdID); err != nil {
		return "", err
	}
	if err := a.markCalendarListed(ctx, to.MemberID, true); err != nil {
		return "", err
	}
	a.republishDatedTodos(ctx, householdID, toToken, newID)
	slog.Info("shared calendar recreated", "household", householdID,
		"from", state.CalendarID, "to", newID, "owner", to.MemberID)
	return newID, nil
}

// republishDatedTodos re-inserts the household's open dated todos into a new
// calendar. Best-effort per todo: a failure marks that todo retry_required
// instead of aborting the handover — losing the calendar mirror is recoverable,
// losing the disconnect is not.
func (a *API) republishDatedTodos(ctx context.Context, householdID, token, calendarID string) {
	rows, err := a.DB.Query(ctx, `
		select id, title, coalesce(origin_label, ''), due_on, recurrence,
			recurrence_until, recurrence_count
		from tasks
		where household_id = $1 and archived_at is null and due_on is not null`, householdID)
	if err != nil {
		slog.Error("calendar handover: list todos", "err", err)
		return
	}
	type todo struct {
		id, title, label string
		due              time.Time
		recurrence       string
		until            *time.Time
		count            *int
	}
	var todos []todo
	for rows.Next() {
		var t todo
		if err := rows.Scan(&t.id, &t.title, &t.label, &t.due, &t.recurrence, &t.until, &t.count); err == nil {
			todos = append(todos, t)
		}
	}
	rows.Close()

	for _, t := range todos {
		payload := google.BuildEvent(t.title, t.label, nil, t.due, "1_day")
		payload.Recurrence = google.RecurrenceRule(t.recurrence, t.until, t.count)
		payload.ExtendedProperties = &google.EventExtendedProperties{
			Private: map[string]string{"evenTaskId": t.id},
		}
		eventID, url, err := a.Google.InsertEvent(ctx, token, calendarID, payload)
		if err != nil {
			slog.Error("calendar handover: republish", "task", t.id, "err", err)
			_ = a.recordCalendarFailure(ctx, t.id,
				"the shared calendar moved to your partner's Google — this todo needs a retry")
			continue
		}
		if _, err := a.DB.Exec(ctx, `
			update tasks set google_event_id = $1, google_event_url = $2,
				calendar_sync_state = 'synced', calendar_last_synced_at = now(),
				calendar_last_error = null
			where id = $3`, eventID, url, t.id); err != nil {
			slog.Error("calendar handover: record event", "task", t.id, "err", err)
		}
	}
}

// ---- ownership transfer --------------------------------------------------

// Mechanisms reported back to the client / logs, in preference order.
const (
	transferACLOwner  = "acl_owner"  // Google accepted an owner-role grant
	transferACLWriter = "acl_writer" // owner role refused; writer keeps Even publishing
	transferRecreate  = "recreate"   // calendar rebuilt under the remaining member
)

// transferCalendarOwnership moves the shared calendar from `from` to `to`.
// It MUST run while `from`'s refresh token is still stored (hard ordering rule
// from the PRD): once the row is deleted there is no owner token left to grant
// anything with.
//
// Preference order, decided at runtime by what Google actually answers:
//  1. patch/insert the partner's ACL rule to role `owner`;
//  2. fall back to `writer` — Even can still publish, Google keeps the old
//     account as nominal owner;
//  3. fall back to recreate + migrate under the partner.
func (a *API) transferCalendarOwnership(ctx context.Context, householdID, householdName string,
	from, to *googleAccount, state calendarState) (string, error) {
	toToken, toErr := a.Google.AccessToken(ctx, to.MemberID, to.RefreshToken, to.ClientKind)
	if toErr != nil {
		return "", toErr // the remaining partner cannot write anything — nothing to transfer to
	}
	fromToken, fromErr := a.Google.AccessToken(ctx, from.MemberID, from.RefreshToken, from.ClientKind)

	if fromErr == nil && to.Email != "" {
		if err := a.grantRole(ctx, fromToken, state.CalendarID, to.Email, google.ACLRoleOwner); err == nil {
			if err := a.adoptTransferred(ctx, householdID, state.CalendarID, to, toToken); err != nil {
				return "", err
			}
			return transferACLOwner, nil
		} else {
			slog.Warn("calendar owner ACL refused — trying writer", "err", err)
		}
		if err := a.grantRole(ctx, fromToken, state.CalendarID, to.Email, google.ACLRoleWriter); err == nil {
			if err := a.adoptTransferred(ctx, householdID, state.CalendarID, to, toToken); err != nil {
				return "", err
			}
			return transferACLWriter, nil
		} else {
			slog.Warn("calendar writer ACL refused — recreating", "err", err)
		}
	} else if fromErr != nil {
		slog.Warn("calendar handover: leaving owner has no usable token", "err", fromErr)
	}

	if _, err := a.recreateCalendarUnder(ctx, householdID, householdName, to, toToken, state); err != nil {
		return "", err
	}
	// Tidy up while the dying token still works; never fatal.
	if fromErr == nil {
		if err := a.Google.DeleteCalendar(ctx, fromToken, state.CalendarID); err != nil {
			slog.Warn("calendar handover: abandoned calendar not deleted", "err", err)
		}
	}
	return transferRecreate, nil
}

// grantRole patches an existing rule, inserting one when the partner has never
// been granted anything. Google answers 404 for a rule that does not exist.
func (a *API) grantRole(ctx context.Context, ownerToken, calendarID, email, role string) error {
	err := a.Google.PatchACL(ctx, ownerToken, calendarID, email, role)
	if err == nil {
		return nil
	}
	return a.Google.InsertACL(ctx, ownerToken, calendarID, email, role)
}

// adoptTransferred records the new owner and makes sure the calendar is on
// their Google list, so it keeps showing after the handover.
func (a *API) adoptTransferred(ctx context.Context, householdID, calendarID string,
	to *googleAccount, toToken string) error {
	if err := a.setCalendarOwner(ctx, householdID, calendarID, to.MemberID); err != nil {
		return err
	}
	if err := a.Google.InsertCalendarList(ctx, toToken, calendarID); err != nil {
		// Already listed (the usual case for a partner who confirmed) or a
		// transient failure; ownership itself has moved.
		slog.Warn("calendar handover: calendarList insert", "err", err)
	}
	return nil
}

// handoverCalendarOnDisconnect runs the calendar side of a disconnect, before
// the token row is deleted. Returns whether ownership moved and a message for
// the remaining partner when it could not.
func (a *API) handoverCalendarOnDisconnect(ctx context.Context, m *Membership) (bool, string) {
	if !a.Google.Configured() {
		return false, ""
	}
	state, err := a.calendarState(ctx, m.HouseholdID)
	if err != nil || !state.ready() {
		return false, ""
	}
	leaving, err := a.googleAccountForMember(ctx, m.MemberID)
	if err != nil {
		return false, ""
	}
	if state.OwnerMemberID != m.MemberID {
		// Not the owner: their mirror simply stops. Revoke the reader grant
		// with the owner's token so a disconnected member keeps no access.
		a.revokeReaderBestEffort(ctx, m, state, leaving)
		return false, ""
	}
	partner := a.otherConnectedAccount(ctx, m.HouseholdID, m.MemberID)
	if partner == nil {
		// Nobody left to own it. The calendar id stays on the household;
		// publishing pauses until someone reconnects and adopts it.
		slog.Info("calendar owner disconnected with no connected partner",
			"household", m.HouseholdID, "calendar", state.CalendarID)
		return false, ""
	}
	mechanism, err := a.transferCalendarOwnership(ctx, m.HouseholdID, m.Household, leaving, partner, state)
	if err != nil {
		slog.Error("calendar ownership transfer failed", "err", err)
		return false, "the shared calendar could not be handed over — reconnect Google to repair it"
	}
	slog.Info("calendar ownership transferred", "household", m.HouseholdID,
		"to", partner.MemberID, "mechanism", mechanism)
	return true, ""
}

func (a *API) revokeReaderBestEffort(ctx context.Context, m *Membership,
	state calendarState, leaving *googleAccount) {
	_ = a.markCalendarListed(ctx, m.MemberID, false)
	if state.OwnerMemberID == "" || leaving.Email == "" {
		return
	}
	owner, err := a.googleAccountForMember(ctx, state.OwnerMemberID)
	if err != nil {
		return
	}
	token, err := a.Google.AccessToken(ctx, owner.MemberID, owner.RefreshToken, owner.ClientKind)
	if err != nil {
		return
	}
	if err := a.Google.DeleteACL(ctx, token, state.CalendarID, leaving.Email); err != nil {
		slog.Warn("calendar reader grant not revoked on disconnect", "err", err)
	}
}

// otherConnectedAccount is the household's *other* connected Google account,
// if any. Only used for calendar ownership — never for mail.
func (a *API) otherConnectedAccount(ctx context.Context, householdID, memberID string) *googleAccount {
	accounts, err := a.householdGoogleAccounts(ctx, householdID)
	if err != nil {
		return nil
	}
	for _, g := range accounts {
		if g.MemberID != memberID {
			return g
		}
	}
	return nil
}

// ---- POST /v1/google/calendar/add ---------------------------------------

// GoogleCalendarAdd is the partner's one-tap confirm: the owner grants them
// **reader** access and the calendar is inserted into their own Google list,
// so `Even — {household}` shows up in Google Calendar without an email invite.
// Mirror-only: they never get writer access — edits belong in Even.
func (a *API) GoogleCalendarAdd(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !a.googleReady(w) {
		return
	}
	caller, err := a.googleAccountForMember(r.Context(), m.MemberID)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusConflict, "not_connected", "connect your Google account first")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "account lookup failed")
		return
	}
	state, err := a.calendarState(r.Context(), m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "calendar lookup failed")
		return
	}
	if !state.ready() {
		httpx.Error(w, http.StatusConflict, "not_ready",
			"the shared calendar doesn't exist yet — approve a dated todo first")
		return
	}
	if state.OwnerMemberID == m.MemberID {
		httpx.Error(w, http.StatusConflict, "already_owner",
			"this calendar already lives on your Google account")
		return
	}
	callerToken, err := a.Google.AccessToken(r.Context(), caller.MemberID, caller.RefreshToken, caller.ClientKind)
	if err != nil {
		a.calendarAddError(w, err, "reconnect_required",
			"Google needs you to reconnect before the calendar can be added")
		return
	}

	owner := a.ownerAccount(r.Context(), state)
	if owner == nil {
		// No connected owner left: the caller adopts the calendar instead of
		// subscribing to one nobody can publish to.
		newID, err := a.recreateCalendarUnder(r.Context(), m.HouseholdID, m.Household, caller, callerToken, state)
		if err != nil {
			a.calendarAddError(w, err, "calendar_failed", "the shared calendar could not be rebuilt")
			return
		}
		httpx.JSON(w, http.StatusOK, map[string]any{
			"calendar_id": newID, "listed": true, "owner": true, "adopted": true,
		})
		return
	}

	ownerToken, err := a.Google.AccessToken(r.Context(), owner.MemberID, owner.RefreshToken, owner.ClientKind)
	if err != nil {
		httpx.Error(w, http.StatusConflict, "owner_reconnect_required",
			"your partner's Google connection needs to be renewed before they can share the calendar")
		return
	}
	if caller.Email == "" {
		httpx.Error(w, http.StatusConflict, "not_connected",
			"reconnect Google so we know which account to share with")
		return
	}
	if err := a.Google.InsertACL(r.Context(), ownerToken, state.CalendarID,
		caller.Email, google.ACLRoleReader); err != nil {
		if errors.Is(err, google.ErrInsufficientScope) {
			httpx.Error(w, http.StatusConflict, "owner_reconnect_required",
				"your partner needs to reconnect Google (calendar permission changed) before sharing")
			return
		}
		slog.Error("calendar acl insert", "err", err)
		httpx.Error(w, http.StatusBadGateway, "calendar_failed",
			"Google would not share the calendar — try again")
		return
	}
	if err := a.Google.InsertCalendarList(r.Context(), callerToken, state.CalendarID); err != nil {
		a.calendarAddError(w, err, "calendar_failed",
			"the calendar was shared but could not be added to your Google list")
		return
	}
	if err := a.markCalendarListed(r.Context(), m.MemberID, true); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not record the subscription")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"calendar_id": state.CalendarID, "listed": true, "owner": false,
	})
}

// calendarAddError keeps a stale-scope failure honest: the app must say
// "reconnect Google", never report a silent success.
func (a *API) calendarAddError(w http.ResponseWriter, err error, code, message string) {
	if errors.Is(err, google.ErrInsufficientScope) {
		httpx.Error(w, http.StatusConflict, "reconnect_required",
			"reconnect Google — Even now needs calendar sharing permission")
		return
	}
	slog.Error("calendar add", "err", err)
	httpx.Error(w, http.StatusBadGateway, code, message)
}

func (a *API) ownerAccount(ctx context.Context, state calendarState) *googleAccount {
	if state.OwnerMemberID == "" {
		return nil
	}
	g, err := a.googleAccountForMember(ctx, state.OwnerMemberID)
	if err != nil {
		return nil
	}
	return g
}
