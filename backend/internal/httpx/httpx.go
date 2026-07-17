package httpx

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

type ctxKey string

const UserIDKey ctxKey = "even.user_id"

// UserID returns the authenticated GoTrue user for the request (set by RequireAuth).
func UserID(r *http.Request) string {
	id, _ := r.Context().Value(UserIDKey).(string)
	return id
}

type AccessVerifier interface {
	VerifyAccess(raw string) (string, error)
}

// RequireAuth gates a subtree behind a valid Bearer access token.
func RequireAuth(v AccessVerifier) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
			if raw == "" || raw == r.Header.Get("Authorization") {
				Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
				return
			}
			userID, err := v.VerifyAccess(raw)
			if err != nil {
				Error(w, http.StatusUnauthorized, "unauthorized", "invalid token")
				return
			}
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), UserIDKey, userID)))
		})
	}
}

// PerUserLimit rate-limits by authenticated user (falls back to remote IP
// pre-auth). Limiters are pruned after an hour idle.
func PerUserLimit(r rate.Limit, burst int) func(http.Handler) http.Handler {
	type entry struct {
		lim  *rate.Limiter
		seen time.Time
	}
	var mu sync.Mutex
	limiters := map[string]*entry{}
	go func() {
		for range time.Tick(10 * time.Minute) {
			mu.Lock()
			for k, e := range limiters {
				if time.Since(e.seen) > time.Hour {
					delete(limiters, k)
				}
			}
			mu.Unlock()
		}
	}()
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			key := UserID(req)
			if key == "" {
				key = req.RemoteAddr
			}
			mu.Lock()
			e, ok := limiters[key]
			if !ok {
				e = &entry{lim: rate.NewLimiter(r, burst)}
				limiters[key] = e
			}
			e.seen = time.Now()
			mu.Unlock()
			if !e.lim.Allow() {
				Error(w, http.StatusTooManyRequests, "rate_limited", "rate limited")
				return
			}
			next.ServeHTTP(w, req)
		})
	}
}

// Recover turns panics into 500s instead of dropped connections.
func Recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				slog.Error("panic", "err", rec, "path", r.URL.Path)
				Error(w, http.StatusInternalServerError, "internal", "internal error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// Log emits one structured line per request — never bodies, never tokens.
func Log(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(sw, r)
		slog.Info("http",
			"method", r.Method, "path", r.URL.Path,
			"status", sw.status, "ms", time.Since(start).Milliseconds())
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func MaxBytes(n int64) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			r.Body = http.MaxBytesReader(w, r.Body, n)
			next.ServeHTTP(w, r)
		})
	}
}

func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// Error writes the API error envelope: {"error":{"code":…,"message":…}}.
func Error(w http.ResponseWriter, status int, code, message string) {
	JSON(w, status, map[string]any{"error": map[string]string{
		"code": code, "message": message,
	}})
}

// Decode parses a JSON body into v with sane failure handling.
func Decode(w http.ResponseWriter, r *http.Request, v any) bool {
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(v); err != nil {
		Error(w, http.StatusBadRequest, "bad_json", "malformed JSON body")
		return false
	}
	return true
}
