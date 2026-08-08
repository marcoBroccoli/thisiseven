package api

import (
	"context"
	"crypto/rand"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/marcoBroccoli/thisiseven/backend/internal/claude"
	"github.com/marcoBroccoli/thisiseven/backend/internal/google"
	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// API carries the handlers' shared state.
type API struct {
	DB        *pgxpool.Pool
	Google    *google.Client
	Claude    *claude.Client
	Hub       *Hub
	AvatarDir string // EVEN_AVATAR_DIR; empty disables avatar write/serve

	syncMu   sync.Mutex
	syncJobs map[string]*syncJob // household id → latest sync job state
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

// activeHouseholdID reads the household the client is currently looking at:
// header `X-Household-Id`, or `?household_id=` for WebSocket upgrades that
// cannot set headers. Empty means "pick for me" — build-12 clients send
// nothing and must keep working.
func activeHouseholdID(r *http.Request) string {
	id := strings.TrimSpace(r.Header.Get("X-Household-Id"))
	if id == "" {
		id = strings.TrimSpace(r.URL.Query().Get("household_id"))
	}
	if id == "" || !uuidRE.MatchString(id) {
		return ""
	}
	return strings.ToLower(id)
}

var uuidRE = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// loadMembership resolves user → member/household/open week for the caller's
// *default* household. A user may belong to several: with no explicit choice
// the most recently joined one wins. Returns pgx.ErrNoRows when the user has
// no membership at all.
func (a *API) loadMembership(ctx context.Context, userID string) (*Membership, error) {
	return a.loadMembershipIn(ctx, userID, "")
}

// loadMembershipIn resolves the caller inside a specific household. An empty
// householdID falls back to the default (most recent) membership.
// pgx.ErrNoRows means "not a member (t)here".
func (a *API) loadMembershipIn(ctx context.Context, userID, householdID string) (*Membership, error) {
	m := &Membership{UserID: userID}
	const cols = `m.id, m.display_name, m.color, h.id, h.name, h.invite_code`
	var err error
	if householdID != "" {
		err = a.DB.QueryRow(ctx, `
			select `+cols+`
			from members m join households h on h.id = m.household_id
			where m.user_id = $1 and m.household_id = $2`, userID, householdID).
			Scan(&m.MemberID, &m.DisplayName, &m.Color, &m.HouseholdID, &m.Household, &m.InviteCode)
	} else {
		err = a.DB.QueryRow(ctx, `
			select `+cols+`
			from members m join households h on h.id = m.household_id
			where m.user_id = $1
			order by m.created_at desc, m.id desc limit 1`, userID).
			Scan(&m.MemberID, &m.DisplayName, &m.Color, &m.HouseholdID, &m.Household, &m.InviteCode)
	}
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
// With `X-Household-Id` the caller picks which one — being no member there is a
// 403, not a "go onboard" 409.
func (a *API) RequireMember(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		want := activeHouseholdID(r)
		m, err := a.loadMembershipIn(r.Context(), httpx.UserID(r), want)
		if errors.Is(err, pgx.ErrNoRows) && want != "" {
			httpx.Error(w, http.StatusForbidden, "not_in_household", "you are not a member of that household")
			return
		}
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
