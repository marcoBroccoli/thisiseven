// Package api is the console's HTTP surface: a JSON API under /api and the
// embedded SPA everywhere else.
//
// Two rules hold everywhere in this package:
//   - reads touch product tables directly and never write to them;
//   - writes go through one of a small, named set of endpoints, and each of
//     those records an admin.audit_log row in the same transaction.
package api

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/marcoBroccoli/thisiseven/admin/internal/store"
)

// API carries everything a handler needs. It is created once in main.
type API struct {
	DB           store.DB
	SessionTTL   time.Duration
	CookieSecure bool
	TOTPIssuer   string
	EvendBaseURL string
	// Now is injected so tests can pin TOTP steps and trend windows.
	Now func() time.Time
	// HTTP is the client used for the evend health probe.
	HTTP *http.Client
}

func (a *API) now() time.Time {
	if a.Now != nil {
		return a.Now()
	}
	return time.Now()
}

func (a *API) httpClient() *http.Client {
	if a.HTTP != nil {
		return a.HTTP
	}
	return &http.Client{Timeout: 3 * time.Second}
}

// ---------------------------------------------------------------- responses

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	if body == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(body); err != nil {
		slog.Error("encode response", "err", err)
	}
}

func writeErr(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, map[string]apiError{"error": {Code: code, Message: msg}})
}

// fail maps an unexpected error to a 500 without leaking the driver's text to
// the browser; the detail goes to the log instead.
func fail(w http.ResponseWriter, op string, err error) {
	if errors.Is(err, context.Canceled) {
		return
	}
	slog.Error("admin handler", "op", op, "err", err)
	writeErr(w, http.StatusInternalServerError, "internal", "Something went wrong on the server.")
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		writeErr(w, http.StatusBadRequest, "bad_json", "Request body is not valid JSON for this endpoint.")
		return false
	}
	return true
}

// ---------------------------------------------------------------- paging

type page struct {
	Limit  int
	Offset int
	Page   int
	Query  string
}

type pageMeta struct {
	Page       int `json:"page"`
	PerPage    int `json:"per_page"`
	Total      int `json:"total"`
	TotalPages int `json:"total_pages"`
}

const defaultPerPage = 25

func readPage(r *http.Request) page {
	p := page{Page: 1, Limit: defaultPerPage}
	if v, err := strconv.Atoi(r.URL.Query().Get("page")); err == nil && v > 0 {
		p.Page = v
	}
	if v, err := strconv.Atoi(r.URL.Query().Get("per_page")); err == nil && v > 0 {
		// Hard ceiling: the console is for looking, not for exporting the db.
		p.Limit = min(v, 200)
	}
	p.Offset = (p.Page - 1) * p.Limit
	p.Query = strings.TrimSpace(r.URL.Query().Get("q"))
	return p
}

func (p page) meta(total int) pageMeta {
	pages := (total + p.Limit - 1) / p.Limit
	return pageMeta{Page: p.Page, PerPage: p.Limit, Total: total, TotalPages: max(pages, 1)}
}

// like turns a free-text search box into an ILIKE pattern. An empty query
// becomes '%', which every row matches — so the caller needs no branch.
func (p page) like() string {
	if p.Query == "" {
		return "%"
	}
	esc := strings.NewReplacer("%", `\%`, "_", `\_`).Replace(p.Query)
	return "%" + esc + "%"
}
