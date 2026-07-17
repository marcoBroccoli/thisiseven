package api

import (
	"context"
	"crypto/rand"
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// API carries the handlers' shared state.
type API struct {
	DB     *pgxpool.Pool
	Google *google.Client
}

// Membership is the resolved caller: member + household + open week. It is
// loaded once per request by RequireMember.
type Membership struct {
	UserID      string
	MemberID    string
	DisplayName string
	Color       string
	HouseholdID string
	Household   string
	InviteCode  string
	WeekID      string
	WeekIndex   int
	WeekStart   time.Time
	// Partner is empty until the second member joins.
	PartnerID   string
	PartnerName string
}

func (m *Membership) HasPartner() bool { return m.PartnerID != "" }

type memberKey struct{}

func membership(r *http.Request) *Membership {
	m, _ := r.Context().Value(memberKey{}).(*Membership)
	return m
}

// loadMembership resolves user → member/household/open week. Returns
// pgx.ErrNoRows when the user has no membership yet.
func (a *API) loadMembership(ctx context.Context, userID string) (*Membership, error) {
	m := &Membership{UserID: userID}
	err := a.DB.QueryRow(ctx, `
		select m.id, m.display_name, m.color, h.id, h.name, h.invite_code
		from members m join households h on h.id = m.household_id
		where m.user_id = $1`, userID).
		Scan(&m.MemberID, &m.DisplayName, &m.Color, &m.HouseholdID, &m.Household, &m.InviteCode)
	if err != nil {
		return nil, err
	}
	err = a.DB.QueryRow(ctx, `
		select id, week_index, started_on from weeks
		where household_id = $1 and closed_at is null`, m.HouseholdID).
		Scan(&m.WeekID, &m.WeekIndex, &m.WeekStart)
	if err != nil {
		return nil, err
	}
	_ = a.DB.QueryRow(ctx, `
		select id, display_name from members
		where household_id = $1 and id <> $2`, m.HouseholdID, m.MemberID).
		Scan(&m.PartnerID, &m.PartnerName) // ErrNoRows fine: solo household
	return m, nil
}

// RequireMember gates /v1 data routes: the caller must belong to a household.
func (a *API) RequireMember(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		m, err := a.loadMembership(r.Context(), httpx.UserID(r))
		if errors.Is(err, pgx.ErrNoRows) {
			httpx.Error(w, http.StatusConflict, "no_household", "join or create a household first")
			return
		}
		if err != nil {
			httpx.Error(w, http.StatusInternalServerError, "internal", "membership lookup failed")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), memberKey{}, m)))
	})
}

// lockHousehold serializes mutations per household inside a transaction.
func lockHousehold(ctx context.Context, tx pgx.Tx, householdID string) error {
	_, err := tx.Exec(ctx, `select 1 from households where id = $1 for update`, householdID)
	return err
}

const codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no O/0/I/1

func newInviteCode() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	for i := range b {
		b[i] = codeAlphabet[int(b[i])%len(codeAlphabet)]
	}
	return string(b)
}

func (m *Membership) requirePartner(w http.ResponseWriter) bool {
	if !m.HasPartner() {
		httpx.Error(w, http.StatusConflict, "no_partner", "your partner hasn't joined yet")
		return false
	}
	return true
}
