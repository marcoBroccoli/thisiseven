package api

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"golang.org/x/time/rate"

	"github.com/marcoBroccoli/thisiseven/backend/internal/httpx"
)

// Router wires the whole surface. Contract: docs/product/API.md.
//   GET  /healthz
//   /auth/*  → GoTrue (Supabase Auth) with the /auth prefix stripped
//   /v1/*    → evend, Bearer-gated
func Router(a *API, verifier httpx.AccessVerifier, gotrueURL string) http.Handler {
	r := chi.NewRouter()
	r.Use(httpx.Recover, httpx.Log)

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		httpx.JSON(w, http.StatusOK, map[string]bool{"ok": true})
	})

	// GoTrue proxy: the app sees ONE origin for auth + data.
	target, err := url.Parse(gotrueURL)
	if err != nil {
		panic("bad gotrue url: " + err.Error())
	}
	proxy := &httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.SetURL(target)
			pr.Out.URL.Path = strings.TrimPrefix(pr.In.URL.Path, "/auth")
			if pr.Out.URL.Path == "" {
				pr.Out.URL.Path = "/"
			}
			pr.Out.Host = target.Host
		},
	}
	r.Handle("/auth/*", http.StripPrefix("", proxy))

	// Onboarding: authenticated, but membership not yet required.
	r.Group(func(r chi.Router) {
		r.Use(httpx.RequireAuth(verifier))
		r.Use(httpx.MaxBytes(64 << 10))
		r.Use(httpx.PerUserLimit(rate.Every(200*time.Millisecond), 30))
		r.Get("/v1/me", a.Me)
		r.Post("/v1/households", a.CreateHousehold)
		r.Post("/v1/households/join", a.JoinHousehold)
	})

	// Data: authenticated + household membership.
	r.Group(func(r chi.Router) {
		r.Use(httpx.RequireAuth(verifier))
		r.Use(a.RequireMember)
		r.Use(httpx.MaxBytes(256 << 10))
		r.Use(httpx.PerUserLimit(rate.Every(100*time.Millisecond), 40))

		r.Get("/v1/summary", a.Summary)

		r.Post("/v1/tasks", a.CreateTask)
		r.Patch("/v1/tasks/{id}", a.UpdateTask)
		r.Delete("/v1/tasks/{id}", a.DeleteTask)
		r.Post("/v1/tasks/{id}/toggle", a.ToggleTask)

		r.Get("/v1/drafts", a.ListDrafts)
		r.Post("/v1/drafts", a.CreateDraft)
		r.Patch("/v1/drafts/{id}", a.UpdateDraft)
		r.Post("/v1/drafts/{id}/approve", a.ApproveDraft)
		r.Post("/v1/drafts/{id}/dismiss", a.DismissDraft)

		r.Get("/v1/money", a.Money)
		r.Post("/v1/expenses", a.CreateExpense)
		r.Post("/v1/settle", a.Settle)

		r.Get("/v1/google/status", a.GoogleStatus)
		r.Post("/v1/google/connect", a.GoogleConnect)
		r.Post("/v1/google/disconnect", a.GoogleDisconnect)
		r.Post("/v1/google/sync", a.GoogleSync)
		r.Get("/v1/google/calendar-info", a.GoogleCalendarInfo)

		r.Get("/v1/calendar", a.Calendar)

		r.Get("/v1/reset", a.Reset)
		r.Put("/v1/appreciations/mine", a.PutAppreciation)
		r.Post("/v1/trades", a.CreateTrade)
		r.Post("/v1/trades/{id}/accept", a.AcceptTrade)
		r.Delete("/v1/trades/{id}", a.DeleteTrade)
		r.Post("/v1/week/close", a.CloseWeek)
	})

	return r
}
