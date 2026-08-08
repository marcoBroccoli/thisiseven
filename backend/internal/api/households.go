package api

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

const (
	maxDisplayNameLen   = 40
	defaultCreatorColor = "#A6552F" // terracotta
	defaultJoinerColor  = "#37756D" // pine
)

var hexColorRE = regexp.MustCompile(`(?i)^#[0-9a-f]{6}$`)

func (a *API) householdJSON(ctx context.Context, householdID, meID string) (HouseholdJSON, error) {
	h := HouseholdJSON{}
	err := a.DB.QueryRow(ctx,
		`select id, name, invite_code from households where id = $1`, householdID).
		Scan(&h.ID, &h.Name, &h.InviteCode)
	if err != nil {
		return h, err
	}
	rows, err := a.DB.Query(ctx, `
		select id, display_name, color, avatar_path is not null
		from members
		where household_id = $1 and left_at is null
		order by created_at`, householdID)
	if err != nil {
		return h, err
	}
	defer rows.Close()
	for rows.Next() {
		var m MemberJSON
		if err := rows.Scan(&m.ID, &m.DisplayName, &m.Color, &m.HasAvatar); err != nil {
			return h, err
		}
		m.Color = canonicalizeMemberColor(m.Color)
		m.IsMe = m.ID == meID
		h.Members = append(h.Members, m)
	}
	return h, rows.Err()
}

// GET /v1/me — the app's routing signal: no member → onboarding.
func (a *API) Me(w http.ResponseWriter, r *http.Request) {
	userID := httpx.UserID(r)
	out := map[string]any{"user_id": userID, "member": nil, "household": nil, "week": nil}
	want := activeHouseholdID(r)
	m, err := a.loadMembershipIn(r.Context(), userID, want)
	if errors.Is(err, pgx.ErrNoRows) && want != "" {
		httpx.Error(w, http.StatusForbidden, "not_in_household", "you are not a member of that household")
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		httpx.JSON(w, http.StatusOK, out)
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	h, err := a.householdJSON(r.Context(), m.HouseholdID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	meJSON, err := a.loadMemberJSON(r.Context(), m.MemberID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	out["member"] = meJSON
	out["household"] = h
	out["week"] = WeekJSON{ID: m.WeekID, Index: m.WeekIndex, StartedOn: dateStr(m.WeekStart)}
	httpx.JSON(w, http.StatusOK, out)
}

// POST /v1/households {name, display_name} — creator gets terracotta, week 1 opens.
func (a *API) CreateHousehold(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name        string `json:"name"`
		DisplayName string `json:"display_name"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	in.Name = strings.TrimSpace(in.Name)
	in.DisplayName = strings.TrimSpace(in.DisplayName)
	if in.Name == "" || in.DisplayName == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_fields", "name and display_name are required")
		return
	}
	// Since multi-household, having one already is no reason to refuse: a user
	// may run their own place and be the partner in another.
	userID := httpx.UserID(r)

	var householdID string
	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		// Invite-code collisions: retry a few times, the space is huge.
		var err error
		for range 5 {
			err = tx.QueryRow(r.Context(), `
				insert into households (name, invite_code) values ($1, $2)
				on conflict (invite_code) do nothing returning id`,
				in.Name, newInviteCode()).Scan(&householdID)
			if err == nil {
				break
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
		}
		if err != nil {
			return err
		}
		if _, err := tx.Exec(r.Context(), `
			insert into members (household_id, user_id, display_name, color)
			values ($1, $2, $3, $4)`, householdID, userID, in.DisplayName, defaultCreatorColor); err != nil {
			return err
		}
		_, err = tx.Exec(r.Context(), `
			insert into weeks (household_id, week_index, started_on)
			values ($1, 1, $2)`, householdID, today())
		return err
	})
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not create household")
		return
	}
	m, _ := a.loadMembershipIn(r.Context(), userID, householdID)
	h, err := a.householdJSON(r.Context(), householdID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusCreated, h)
}

// POST /v1/households/join {invite_code, display_name} — joiner gets pine.
func (a *API) JoinHousehold(w http.ResponseWriter, r *http.Request) {
	var in struct {
		InviteCode  string `json:"invite_code"`
		DisplayName string `json:"display_name"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	in.InviteCode = strings.ToUpper(strings.TrimSpace(in.InviteCode))
	in.DisplayName = strings.TrimSpace(in.DisplayName)
	if in.InviteCode == "" || in.DisplayName == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_fields", "invite_code and display_name are required")
		return
	}
	// Belonging to another household is fine now; belonging to *this* one is not.
	userID := httpx.UserID(r)

	var householdID string
	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		err := tx.QueryRow(r.Context(),
			`select id from households where invite_code = $1`, in.InviteCode).Scan(&householdID)
		if err != nil {
			return err
		}
		if err := lockHousehold(r.Context(), tx, householdID); err != nil {
			return err
		}
		return seatMember(r.Context(), tx, householdID, userID, in.DisplayName, defaultJoinerColor)
	})
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		httpx.Error(w, http.StatusNotFound, "bad_code", "no household with that code")
		return
	case errors.Is(err, errHouseholdFull):
		httpx.Error(w, http.StatusConflict, "household_full", "this household already has two people")
		return
	case errors.Is(err, errAlreadyMember):
		httpx.Error(w, http.StatusConflict, "already_in_household", "you already belong to this household")
		return
	case err != nil:
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not join household")
		return
	}
	m, _ := a.loadMembershipIn(r.Context(), userID, householdID)
	h, err := a.householdJSON(r.Context(), householdID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, h)
}

var (
	errHouseholdFull = errors.New("household full")
	errAlreadyMember = errors.New("already a member of this household")
)

// seatMember takes the household's second seat (invite code or email invite).
// Caller holds the household lock. `want` is the colour the flow would like;
// if the sitting member already wears it the newcomer gets the other half of
// the pair, so a household never reads as one person twice.
//
// Somebody who left this household before is *revived*, not inserted again:
// unique (user_id, household_id) allows exactly one row per person per
// household, and the history hanging off that row is theirs. They come back
// with the name and colour of this arrival — a return is a new start, not a
// restore. Only an **active** membership is `already_in_household`.
func seatMember(ctx context.Context, tx pgx.Tx, householdID, userID, displayName, want string) error {
	rows, err := tx.Query(ctx,
		`select user_id, color, left_at is null from members where household_id = $1`, householdID)
	if err != nil {
		return err
	}
	taken := map[string]bool{}
	count := 0
	mine, returning := false, false
	for rows.Next() {
		var uid, color string
		var active bool
		if err := rows.Scan(&uid, &color, &active); err != nil {
			rows.Close()
			return err
		}
		if active {
			count++
			taken[canonicalizeMemberColor(color)] = true
		}
		if uid == userID {
			mine = active
			returning = !active
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	if mine {
		return errAlreadyMember
	}
	if count >= 2 {
		return errHouseholdFull
	}
	color := want
	if taken[color] {
		if color == defaultCreatorColor {
			color = defaultJoinerColor
		} else {
			color = defaultCreatorColor
		}
	}
	if returning {
		_, err = tx.Exec(ctx, `
			update members set left_at = null, display_name = $1, color = $2
			where household_id = $3 and user_id = $4`,
			displayName, color, householdID, userID)
		return err
	}
	_, err = tx.Exec(ctx, `
		insert into members (household_id, user_id, display_name, color)
		values ($1, $2, $3, $4)`, householdID, userID, displayName, color)
	return err
}

// PATCH /v1/me {display_name?, color?} — update the caller's member row.
// color is #RRGGBB (legacy "clay"/"teal" accepted and normalized).
func (a *API) UpdateMe(w http.ResponseWriter, r *http.Request) {
	var in struct {
		DisplayName *string `json:"display_name"`
		Color       *string `json:"color"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	if in.DisplayName == nil && in.Color == nil {
		httpx.Error(w, http.StatusBadRequest, "missing_fields", "display_name or color is required")
		return
	}

	var displayName string
	if in.DisplayName != nil {
		displayName = strings.TrimSpace(*in.DisplayName)
		if displayName == "" {
			httpx.Error(w, http.StatusBadRequest, "invalid_display_name", "display_name cannot be empty")
			return
		}
		if len([]rune(displayName)) > maxDisplayNameLen {
			httpx.Error(w, http.StatusBadRequest, "invalid_display_name", "display_name is too long")
			return
		}
	}

	var color string
	if in.Color != nil {
		normalized, ok := normalizeMemberColor(*in.Color)
		if !ok {
			httpx.Error(w, http.StatusBadRequest, "invalid_color", "color must be #RRGGBB")
			return
		}
		color = normalized
	}

	m := membership(r)
	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		if in.DisplayName != nil {
			if _, err := tx.Exec(r.Context(),
				`update members set display_name = $1 where id = $2`,
				displayName, m.MemberID); err != nil {
				return err
			}
		}
		if in.Color == nil {
			return nil
		}
		_, err := tx.Exec(r.Context(),
			`update members set color = $1 where id = $2`, color, m.MemberID)
		return err
	})
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not update profile")
		return
	}

	out, err := a.loadMemberJSON(r.Context(), m.MemberID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, out)
}

func normalizeMemberColor(s string) (string, bool) {
	s = strings.TrimSpace(s)
	switch strings.ToLower(s) {
	case "clay":
		return defaultCreatorColor, true
	case "teal":
		return defaultJoinerColor, true
	}
	if !hexColorRE.MatchString(s) {
		return "", false
	}
	return strings.ToUpper(s), true
}

func canonicalizeMemberColor(s string) string {
	if out, ok := normalizeMemberColor(s); ok {
		return out
	}
	return s
}
