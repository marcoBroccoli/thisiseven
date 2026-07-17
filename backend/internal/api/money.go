package api

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

type moneyPayload struct {
	BalanceCents     int64          `json:"balance_cents"`
	DebtorMemberID   *string        `json:"debtor_member_id"`
	CreditorMemberID *string        `json:"creditor_member_id"`
	Feed             []FeedItemJSON `json:"feed"`
}

// balance computes who owes whom over unsettled expenses. Positive result:
// debtor owes creditor half the difference (rounded up on odd cents).
func (a *API) balance(ctx context.Context, q pgx.Tx, m *Membership) (bal int64, debtor, creditor string, err error) {
	if !m.HasPartner() {
		return 0, "", "", nil // solo: nothing to split yet
	}
	rows, err := query(ctx, q, a, `
		select paid_by_member_id, coalesce(sum(amount_cents), 0)
		from expenses where household_id = $1 and settlement_id is null
		group by paid_by_member_id`, m.HouseholdID)
	if err != nil {
		return 0, "", "", err
	}
	defer rows.Close()
	sums := map[string]int64{}
	for rows.Next() {
		var id string
		var sum int64
		if err := rows.Scan(&id, &sum); err != nil {
			return 0, "", "", err
		}
		sums[id] = sum
	}
	if rows.Err() != nil {
		return 0, "", "", rows.Err()
	}
	mine, partners := sums[m.MemberID], sums[m.PartnerID]
	diff := mine - partners
	if diff == 0 {
		return 0, "", "", nil
	}
	if diff > 0 {
		return (diff + 1) / 2, m.PartnerID, m.MemberID, nil
	}
	return (-diff + 1) / 2, m.MemberID, m.PartnerID, nil
}

// query runs on the tx when present, else the pool — lets balance() serve
// both the GET path and the settle transaction.
func query(ctx context.Context, tx pgx.Tx, a *API, sql string, args ...any) (pgx.Rows, error) {
	if tx != nil {
		return tx.Query(ctx, sql, args...)
	}
	return a.DB.Query(ctx, sql, args...)
}

func (a *API) moneyPayload(ctx context.Context, m *Membership) (*moneyPayload, error) {
	bal, debtor, creditor, err := a.balance(ctx, nil, m)
	if err != nil {
		return nil, err
	}
	out := &moneyPayload{BalanceCents: bal, Feed: []FeedItemJSON{}}
	if debtor != "" {
		out.DebtorMemberID, out.CreditorMemberID = &debtor, &creditor
	}

	// Feed: current cycle's expenses + the last settlement + what it cleared.
	rows, err := a.DB.Query(ctx, `
		with last_settlement as (
			select id from settlements where household_id = $1
			order by created_at desc limit 1
		)
		select 'expense', e.id::text, e.title, e.amount_cents,
		       e.paid_by_member_id::text, e.incurred_on::text,
		       (e.settlement_id is not null), '', '', e.created_at
		from expenses e
		where e.household_id = $1
		  and (e.settlement_id is null or e.settlement_id in (select id from last_settlement))
		union all
		select 'settlement', s.id::text, '', s.amount_cents, '', '', false,
		       s.from_member_id::text, s.to_member_id::text, s.created_at
		from settlements s
		where s.household_id = $1 and s.id in (select id from last_settlement)
		order by 10 desc`, m.HouseholdID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var f FeedItemJSON
		var createdAt time.Time
		if err := rows.Scan(&f.Kind, &f.ID, &f.Title, &f.AmountCents,
			&f.PaidByMemberID, &f.IncurredOn, &f.Settled,
			&f.FromMemberID, &f.ToMemberID, &createdAt); err != nil {
			return nil, err
		}
		if f.Kind == "settlement" {
			f.CreatedAt = createdAt.UTC().Format(time.RFC3339)
		}
		out.Feed = append(out.Feed, f)
	}
	return out, rows.Err()
}

// GET /v1/money
func (a *API) Money(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	p, err := a.moneyPayload(r.Context(), m)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "money lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

// POST /v1/expenses
func (a *API) CreateExpense(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	var in struct {
		Title          string `json:"title"`
		AmountCents    int64  `json:"amount_cents"`
		PaidByMemberID string `json:"paid_by_member_id"`
		IncurredOn     string `json:"incurred_on"`
	}
	if !httpx.Decode(w, r, &in) {
		return
	}
	in.Title = strings.TrimSpace(in.Title)
	if in.Title == "" || in.AmountCents <= 0 || in.PaidByMemberID == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_fields",
			"title, positive amount_cents and paid_by_member_id are required")
		return
	}
	if !strings.EqualFold(in.PaidByMemberID, m.MemberID) && !strings.EqualFold(in.PaidByMemberID, m.PartnerID) {
		httpx.Error(w, http.StatusNotFound, "not_found", "payer is not in this household")
		return
	}
	incurred := today()
	if in.IncurredOn != "" {
		d, err := time.Parse("2006-01-02", in.IncurredOn)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "bad_date", "incurred_on must be YYYY-MM-DD")
			return
		}
		incurred = d
	}
	var id string
	err := a.DB.QueryRow(r.Context(), `
		insert into expenses (household_id, title, amount_cents, paid_by_member_id, incurred_on)
		values ($1, $2, $3, $4, $5) returning id`,
		m.HouseholdID, in.Title, in.AmountCents, in.PaidByMemberID, incurred).Scan(&id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not add expense")
		return
	}
	p, err := a.moneyPayload(r.Context(), m)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "money lookup failed")
		return
	}
	httpx.JSON(w, http.StatusCreated, p)
}

// POST /v1/settle — one transaction: settlement row + expenses marked settled.
func (a *API) Settle(w http.ResponseWriter, r *http.Request) {
	m := membership(r)
	if !m.requirePartner(w) {
		return
	}
	err := pgx.BeginFunc(r.Context(), a.DB, func(tx pgx.Tx) error {
		if err := lockHousehold(r.Context(), tx, m.HouseholdID); err != nil {
			return err
		}
		bal, debtor, creditor, err := a.balance(r.Context(), tx, m)
		if err != nil {
			return err
		}
		if bal == 0 {
			return errAlreadyEven
		}
		var sid string
		if err := tx.QueryRow(r.Context(), `
			insert into settlements (household_id, from_member_id, to_member_id, amount_cents)
			values ($1, $2, $3, $4) returning id`,
			m.HouseholdID, debtor, creditor, bal).Scan(&sid); err != nil {
			return err
		}
		_, err = tx.Exec(r.Context(), `
			update expenses set settlement_id = $1
			where household_id = $2 and settlement_id is null`, sid, m.HouseholdID)
		return err
	})
	if errors.Is(err, errAlreadyEven) {
		httpx.Error(w, http.StatusConflict, "already_even", "you're already even on money")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "could not settle")
		return
	}
	p, err := a.moneyPayload(r.Context(), m)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "money lookup failed")
		return
	}
	httpx.JSON(w, http.StatusOK, p)
}

var errAlreadyEven = errors.New("already even")
