package api

import (
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

// Router wires the whole service. Read it as the contract: everything under
// /api/* that is not the login pair requires a session, and everything that
// mutates additionally requires the writer role.
func Router(a *API, spa http.Handler) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RealIP)
	r.Use(middleware.RequestID)
	r.Use(recoverer)
	r.Use(requestLog)
	r.Use(securityHeaders)

	// Liveness for compose / Uptime Kuma. Deliberately outside the session
	// gate and deliberately says nothing about the data.
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	})

	r.Route("/api", func(r chi.Router) {
		r.Post("/auth/login", a.Login)
		r.Post("/auth/totp", a.VerifyTOTP)
		r.Post("/auth/logout", a.Logout)

		r.Group(func(r chi.Router) {
			r.Use(a.RequireAdmin)

			r.Get("/auth/me", a.Me)
			r.Get("/dashboard", a.Dashboard)
			r.Get("/users", a.ListUsers)
			r.Get("/users/{id}", a.GetUser)
			r.Get("/households", a.ListHouseholds)
			r.Get("/households/{id}", a.GetHousehold)
			r.Get("/ops", a.Ops)
			r.Get("/settings", a.ListSettings)
			r.Get("/notifications", a.ListNotifications)
			r.Get("/notifications/targets", a.NotificationTargets)
			r.Get("/audit", a.ListAudit)
			r.Get("/health", a.Health)

			r.Group(func(r chi.Router) {
				r.Use(a.RequireWriter)

				r.Post("/auth/password", a.ChangePassword)
				r.Post("/households/{id}/invites/{inviteID}/revoke", a.RevokeInvite)
				r.Post("/households/{id}/invite-code/regenerate", a.RegenerateInviteCode)
				r.Post("/settings", a.UpsertSetting)
				r.Put("/settings/{key}", a.UpsertSetting)
				r.Delete("/settings/{key}", a.DeleteSetting)
				r.Post("/notifications", a.CreateNotification)
				r.Post("/notifications/{id}/cancel", a.CancelNotification)
			})
		})

		// An unmatched /api/* path must be JSON, not the SPA's index.html —
		// otherwise a typo'd fetch resolves to HTML and fails at parse time
		// with a message about "<" that says nothing useful.
		r.NotFound(func(w http.ResponseWriter, _ *http.Request) {
			writeErr(w, http.StatusNotFound, "no_route", "No such endpoint.")
		})
		r.MethodNotAllowed(func(w http.ResponseWriter, _ *http.Request) {
			writeErr(w, http.StatusMethodNotAllowed, "bad_method", "Wrong method for this endpoint.")
		})
	})

	r.Handle("/*", spa)
	return r
}

func recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				slog.Error("panic", "err", rec, "path", r.URL.Path)
				writeErr(w, http.StatusInternalServerError, "internal", "Something went wrong on the server.")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func requestLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Only the API is logged: static asset noise would bury it, and the
		// console serves a few hundred files per cold load.
		if !strings.HasPrefix(r.URL.Path, "/api/") {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)
		slog.Info("req",
			"method", r.Method, "path", r.URL.Path,
			"status", ww.Status(), "ms", time.Since(start).Milliseconds(),
			"ip", clientIP(r))
	})
}

// securityHeaders locks the page down to itself. The console loads no third
// party anything — the SPA bundle is built into the binary — so the policy can
// be absolute rather than a list of allowances.
func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Permissions-Policy", "camera=(), microphone=(), geolocation=(), interest-cohort=()")
		h.Set("Content-Security-Policy",
			"default-src 'self'; "+
				"script-src 'self'; "+
				// Vite emits one stylesheet, but inline styles are still used for
				// dynamic chart geometry, so 'unsafe-inline' stays for style only.
				"style-src 'self' 'unsafe-inline'; "+
				"img-src 'self' data:; "+
				"font-src 'self' data:; "+
				"connect-src 'self'; "+
				"frame-ancestors 'none'; "+
				"base-uri 'none'; "+
				"form-action 'self'")
		next.ServeHTTP(w, r)
	})
}
