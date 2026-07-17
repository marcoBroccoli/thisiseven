package api

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

func (a *API) householdJSON(ctx context.Context, householdID, meID string) (HouseholdJSON, error) {
	h := HouseholdJSON{}
	err := a.DB.QueryRow(ctx,
		`select id, name, invite_code from households where id = $1`, householdID).
		Scan(&h.ID, &h.Name, &h.InviteCode)
	if err != nil {
		return h, err
	}
	rows, err := a.DB.Query(ctx, `
		select id, display_name, color from members
		where household_id = $1 order by created_at`, householdID)
	if err != nil {
		return h, err
	}
	defer rows.Close()
	for rows.Next() {
		var m MemberJSON
		if err := rows.Scan(&m.ID, &m.DisplayName, &m.Color); err != nil {
			return h, err
		}
		m.IsMe = m.ID == meID
		h.Members = append(h.Members, m)
	}
	return h, rows.Err()
}

// GET /v1/me — the app's routing signal: no member → onboarding.
func (a *API) Me(w http.ResponseWriter, r *http.Request) {
	userID := httpx.UserID(r)
	out := map[string]any{"user_id": userID, "member": nil, "household": nil, "week": nil}
	m, err := a.loadMembership(r.Context(), userID)
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
	out["member"] = MemberJSON{ID: m.MemberID, DisplayName: m.DisplayName, Color: m.Color, IsMe: true}
	out["household"] = h
	out["week"] = WeekJSON{ID: m.WeekID, Index: m.WeekIndex, StartedOn: dateStr(m.WeekStart)}
	httpx.JSON(w, http.StatusOK, out)
}

// POST /v1/households {name, display_name} — creator gets clay, week 1 opens.
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
	userID := httpx.UserID(r)
	if _, err := a.loadMembership(r.Context(), userID); err == nil {
		httpx.Error(w, http.StatusConflict, "already_in_household", "you already belong to a household")
		return
	}

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
			values ($1, $2, $3, 'clay')`, householdID, userID, in.DisplayName); err != nil {
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
	m, _ := a.loadMembership(r.Context(), userID)
	h, err := a.householdJSON(r.Context(), householdID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusCreated, h)
}

// POST /v1/households/join {invite_code, display_name} — joiner gets teal.
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
	userID := httpx.UserID(r)
	if _, err := a.loadMembership(r.Context(), userID); err == nil {
		httpx.Error(w, http.StatusConflict, "already_in_household", "you already belong to a household")
		return
	}

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
		var count int
		if err := tx.QueryRow(r.Context(),
			`select count(*) from members where household_id = $1`, householdID).Scan(&count); err != nil {
			return err
		}
		if count >= 2 {
			return errHouseholdFull
		}
		_, err = tx.Exec(r.Context(), `
			insert into members (household_id, user_id, display_name, color)
			values ($1, $2, $3, 'teal')`, householdID, userID, in.DisplayName)
		return err
	})
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		httpx.Error(w, http.StatusNotFound, "bad_code", "no household with that code")
		return
	case errors.Is(err, errHouseholdFull):
		httpx.Error(w, http.StatusConflict, "household_full", "this household already has two people")
		return
	case err != nil:
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not join household")
		return
	}
	m, _ := a.loadMembership(r.Context(), userID)
	h, err := a.householdJSON(r.Context(), householdID, m.MemberID)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, h)
}

var errHouseholdFull = errors.New("household full")
