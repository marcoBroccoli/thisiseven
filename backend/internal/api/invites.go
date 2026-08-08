package api

// Multi-household membership and email invites.
//
// evend sends no mail. An invite is a *record*: the owner types their
// partner's address, and the next time a signed-in user whose GoTrue email
// matches lists their households the invite is sitting there to accept or
// decline. The invite_code flow is untouched — this is the second door.

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

const maxInviteEmailLen = 320

// userEmail reads the caller's address from GoTrue. Empty when it cannot be
// resolved (no row, no email, or no auth schema in this deployment) — an
// unknown address simply matches no invites, it is never an error the client
// has to handle.
func (a *API) userEmail(ctx context.Context, userID string) string {
	var email *string
	if err := a.DB.QueryRow(ctx,
		`select email from auth.users where id = $1`, userID).Scan(&email); err != nil {
		return ""
	}
	if email == nil {
		return ""
	}
	return normalizeEmail(*email)
}

func normalizeEmail(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

// plausibleEmail is a shape check, not validation — nothing is delivered, the
// address only has to match what GoTrue stored for the other person.
func plausibleEmail(s string) bool {
	if s == "" || len(s) > maxInviteEmailLen || strings.ContainsAny(s, " \t\r\n") {
		return false
	}
	at := strings.IndexByte(s, '@')
	return at > 0 && at < len(s)-1 && strings.Contains(s[at+1:], ".")
}

// GET /v1/households → every household the caller belongs to, plus the email
// invites waiting for them. Membership is NOT required: a brand-new user with
// an invite must be able to see it before they belong anywhere.
func (a *API) ListHouseholds(w http.ResponseWriter, r *http.Request) {
	userID := httpx.UserID(r)
	ctx := r.Context()

	// One row per membership; the creator is the household's first member.
	rows, err := a.DB.Query(ctx, `
		select h.id, h.name, h.invite_code, m.id,
		       (select count(*) from members x where x.household_id = h.id),
		       m.id = (select f.id from members f where f.household_id = h.id
		               order by f.created_at, f.id limit 1),
		       (select i.email from household_invites i
		        where i.household_id = h.id and i.status = 'pending' limit 1)
		from members m join households h on h.id = m.household_id
		where m.user_id = $1
		order by m.created_at, m.id`, userID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	defer rows.Close()
	households := []HouseholdListItemJSON{}
	for rows.Next() {
		var it HouseholdListItemJSON
		if err := rows.Scan(&it.ID, &it.Name, &it.InviteCode, &it.MyMemberID,
			&it.MemberCount, &it.IsOwner, &it.PendingInviteEmail); err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
			return
		}
		households = append(households, it)
	}
	if err := rows.Err(); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}

	invites, err := a.pendingInvitesFor(ctx, userID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"households": households, "invites": invites,
	})
}

// pendingInvitesFor lists the live invites addressed to this user's email. An
// invite to a household they already sit in is filtered out — that seat is
// theirs already.
func (a *API) pendingInvitesFor(ctx context.Context, userID string) ([]InviteJSON, error) {
	out := []InviteJSON{}
	email := a.userEmail(ctx, userID)
	if email == "" {
		return out, nil
	}
	rows, err := a.DB.Query(ctx, `
		select i.id, i.household_id, h.name, m.display_name, i.email, i.status, i.created_at
		from household_invites i
		join households h on h.id = i.household_id
		join members m on m.id = i.invited_by_member_id
		where i.status = 'pending' and i.email = $1
		  and not exists (select 1 from members me
		                  where me.household_id = i.household_id and me.user_id = $2)
		order by i.created_at`, email, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var iv InviteJSON
		var created time.Time
		if err := rows.Scan(&iv.ID, &iv.HouseholdID, &iv.HouseholdName,
			&iv.InvitedByName, &iv.Email, &iv.Status, &created); err != nil {
			return nil, err
		}
		iv.CreatedAt = created.UTC().Format(time.RFC3339)
		out = append(out, iv)
	}
	return out, rows.Err()
}

// POST /v1/households/{id}/invite {email} — record the empty seat's invite.
// Either member may write it: a household holds two people, so whoever is
// already inside is the one with a seat to give.
func (a *API) InviteToHousehold(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email string `json:"email"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	email := normalizeEmail(in.Email)
	if !plausibleEmail(email) {
		httpx.Error(w, http.StatusBadRequest, "invalid_email", "that does not look like an email address")
		return
	}
	userID := httpx.UserID(r)
	m, ok := a.memberOfPath(w, r)
	if !ok {
		return
	}
	if mine := a.userEmail(r.Context(), userID); mine != "" && mine == email {
		httpx.Error(w, http.StatusUnprocessableEntity, "self_invite", "that is your own address")
		return
	}

	var iv InviteJSON
	var created time.Time
	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		if err := lockHousehold(r.Context(), tx, m.HouseholdID); err != nil {
			return err
		}
		var count int
		if err := tx.QueryRow(r.Context(),
			`select count(*) from members where household_id = $1`, m.HouseholdID).Scan(&count); err != nil {
			return err
		}
		if count >= 2 {
			return errHouseholdFull
		}
		var exists bool
		if err := tx.QueryRow(r.Context(), `select exists(
			select 1 from household_invites
			where household_id = $1 and status = 'pending')`, m.HouseholdID).Scan(&exists); err != nil {
			return err
		}
		if exists {
			return errInvitePending
		}
		return tx.QueryRow(r.Context(), `
			insert into household_invites (household_id, email, invited_by_member_id)
			values ($1, $2, $3)
			returning id, household_id, email, status, created_at`,
			m.HouseholdID, email, m.MemberID).
			Scan(&iv.ID, &iv.HouseholdID, &iv.Email, &iv.Status, &created)
	})
	switch {
	case errors.Is(err, errHouseholdFull):
		httpx.Error(w, http.StatusConflict, "household_full", "this household already has two people")
		return
	case errors.Is(err, errInvitePending):
		httpx.Error(w, http.StatusConflict, "invite_pending", "an invite for the free seat is already out")
		return
	case err != nil:
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not create the invite")
		return
	}
	iv.HouseholdName = m.Household
	iv.InvitedByName = m.DisplayName
	iv.CreatedAt = created.UTC().Format(time.RFC3339)
	httpx.JSON(w, http.StatusCreated, iv)
}

// DELETE /v1/households/{id}/invite — take the outstanding invite back.
func (a *API) RevokeHouseholdInvite(w http.ResponseWriter, r *http.Request) {
	m, ok := a.memberOfPath(w, r)
	if !ok {
		return
	}
	tag, err := a.DB.Exec(r.Context(), `
		update household_invites set status = 'revoked', responded_at = now()
		where household_id = $1 and status = 'pending'`, m.HouseholdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not revoke the invite")
		return
	}
	if tag.RowsAffected() == 0 {
		httpx.Error(w, http.StatusNotFound, "no_invite", "there is no invite out for this household")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// POST /v1/invites/{id}/accept {display_name} → household — take the seat.
func (a *API) AcceptInvite(w http.ResponseWriter, r *http.Request) {
	var in struct {
		DisplayName string `json:"display_name"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	in.DisplayName = strings.TrimSpace(in.DisplayName)
	if in.DisplayName == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_fields", "display_name is required")
		return
	}
	if len([]rune(in.DisplayName)) > maxDisplayNameLen {
		httpx.Error(w, http.StatusBadRequest, "invalid_display_name", "display_name is too long")
		return
	}
	userID := httpx.UserID(r)
	inviteID, householdID, ok := a.inviteForCaller(w, r)
	if !ok {
		return
	}

	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		if err := lockHousehold(r.Context(), tx, householdID); err != nil {
			return err
		}
		if err := seatMember(r.Context(), tx, householdID, userID, in.DisplayName, defaultJoinerColor); err != nil {
			return err
		}
		_, err := tx.Exec(r.Context(), `
			update household_invites set status = 'accepted', responded_at = now()
			where id = $1 and status = 'pending'`, inviteID)
		return err
	})
	switch {
	case errors.Is(err, errHouseholdFull):
		httpx.Error(w, http.StatusConflict, "household_full", "this household already has two people")
		return
	case errors.Is(err, errAlreadyMember):
		httpx.Error(w, http.StatusConflict, "already_in_household", "you already belong to this household")
		return
	case err != nil:
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not accept the invite")
		return
	}
	m, err := a.loadMembershipIn(r.Context(), userID, householdID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	h, err := a.householdJSON(r.Context(), householdID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, h)
}

// POST /v1/invites/{id}/decline — say no; the seat stays empty and the owner
// may invite someone else.
func (a *API) DeclineInvite(w http.ResponseWriter, r *http.Request) {
	inviteID, _, ok := a.inviteForCaller(w, r)
	if !ok {
		return
	}
	if _, err := a.DB.Exec(r.Context(), `
		update household_invites set status = 'declined', responded_at = now()
		where id = $1 and status = 'pending'`, inviteID); err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not decline the invite")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]bool{"ok": true})
}

var errInvitePending = errors.New("invite already pending")

// memberOfPath resolves the caller inside the household named in the URL —
// invite routes are addressed by household, not by the active-household
// header. Writes the error response itself; ok=false means it is handled.
func (a *API) memberOfPath(w http.ResponseWriter, r *http.Request) (*Membership, bool) {
	id := strings.ToLower(strings.TrimSpace(chi.URLParam(r, "id")))
	if !uuidRE.MatchString(id) {
		httpx.Error(w, http.StatusForbidden, "not_in_household", "you are not a member of that household")
		return nil, false
	}
	m, err := a.loadMembershipIn(r.Context(), httpx.UserID(r), id)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusForbidden, "not_in_household", "you are not a member of that household")
		return nil, false
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "membership lookup failed")
		return nil, false
	}
	return m, true
}

// inviteForCaller loads a pending invite by id and proves it is addressed to
// the caller's own email. A mismatch is a 404 — an invite you were not sent
// does not exist as far as you are concerned.
func (a *API) inviteForCaller(w http.ResponseWriter, r *http.Request) (inviteID, householdID string, ok bool) {
	id := strings.ToLower(strings.TrimSpace(chi.URLParam(r, "id")))
	if !uuidRE.MatchString(id) {
		httpx.Error(w, http.StatusNotFound, "no_invite", "no invite waiting for you")
		return "", "", false
	}
	email := a.userEmail(r.Context(), httpx.UserID(r))
	if email == "" {
		httpx.Error(w, http.StatusNotFound, "no_invite", "no invite waiting for you")
		return "", "", false
	}
	err := a.DB.QueryRow(r.Context(), `
		select id, household_id from household_invites
		where id = $1 and status = 'pending' and email = $2`, id, email).
		Scan(&inviteID, &householdID)
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "no_invite", "no invite waiting for you")
		return "", "", false
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return "", "", false
	}
	return inviteID, householdID, true
}
