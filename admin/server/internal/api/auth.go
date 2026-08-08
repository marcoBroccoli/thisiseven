package api

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/marcoBroccoli/thisiseven/admin/internal/adminauth"
)

const (
	sessionCookie   = "even_admin_session"
	challengeCookie = "even_admin_challenge"
	// A challenge is the seconds between "password accepted" and "code typed".
	// Five minutes is generous for reading a QR code and stingy for anyone who
	// stole the half-authenticated cookie.
	challengeTTL = 5 * time.Minute
	// A challenge dies after this many wrong codes, forcing the password step
	// again — so the 6-digit space cannot be walked inside one challenge.
	maxChallengeAttempts = 5
	// Rate limit: failures per email or per IP inside the window.
	loginWindow      = 15 * time.Minute
	maxFailsPerEmail = 8
	maxFailsPerIP    = 20
)

// ---------------------------------------------------------------- identity

type Admin struct {
	ID     string `json:"id"`
	Email  string `json:"email"`
	Role   string `json:"role"`
	MFA    bool   `json:"mfa_enrolled"`
	Expiry string `json:"session_expires_at"`
}

type ctxKey int

const adminCtxKey ctxKey = 1

func adminFrom(ctx context.Context) (Admin, bool) {
	a, ok := ctx.Value(adminCtxKey).(Admin)
	return a, ok
}

// RequireAdmin resolves the session cookie to a live, non-expired, non-revoked
// session belonging to a non-disabled account. Anything else is 401.
func (a *API) RequireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c, err := r.Cookie(sessionCookie)
		if err != nil || c.Value == "" {
			writeErr(w, http.StatusUnauthorized, "no_session", "Sign in to continue.")
			return
		}
		var adm Admin
		var expires time.Time
		var enrolled *time.Time
		err = a.DB.QueryRow(r.Context(), `
			select u.id::text, u.email, u.role, u.totp_enrolled_at, s.expires_at
			  from admin.sessions s
			  join admin.admin_users u on u.id = s.admin_user_id
			 where s.token_hash = $1
			   and s.revoked_at is null
			   and s.expires_at > now()
			   and u.disabled_at is null`,
			adminauth.HashToken(c.Value)).Scan(&adm.ID, &adm.Email, &adm.Role, &enrolled, &expires)
		if errors.Is(err, pgx.ErrNoRows) {
			a.clearCookie(w, sessionCookie)
			writeErr(w, http.StatusUnauthorized, "no_session", "Your session has expired. Sign in again.")
			return
		}
		if err != nil {
			fail(w, "resolve session", err)
			return
		}
		adm.MFA = enrolled != nil
		adm.Expiry = expires.UTC().Format(time.RFC3339)
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), adminCtxKey, adm)))
	})
}

// RequireWriter blocks the read-only role from any mutating endpoint. It is a
// second gate behind the router's method routing, not a replacement for it.
func (a *API) RequireWriter(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		adm, ok := adminFrom(r.Context())
		if !ok || adm.Role != "admin" {
			writeErr(w, http.StatusForbidden, "read_only",
				"This account can view the console but not change anything.")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// ---------------------------------------------------------------- cookies

func (a *API) setCookie(w http.ResponseWriter, name, value string, ttl time.Duration) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    value,
		Path:     "/",
		HttpOnly: true,
		Secure:   a.CookieSecure,
		SameSite: http.SameSiteLaxMode,
		Expires:  a.now().Add(ttl),
		MaxAge:   int(ttl.Seconds()),
	})
}

func (a *API) clearCookie(w http.ResponseWriter, name string) {
	http.SetCookie(w, &http.Cookie{
		Name: name, Value: "", Path: "/", HttpOnly: true,
		Secure: a.CookieSecure, SameSite: http.SameSiteLaxMode, MaxAge: -1,
	})
}

func clientIP(r *http.Request) string {
	// Behind Caddy / the Cloudflare tunnel the socket peer is the proxy, so the
	// forwarded chain is the only honest source. First hop wins.
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if first, _, ok := strings.Cut(xff, ","); ok {
			return strings.TrimSpace(first)
		}
		return strings.TrimSpace(xff)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// ---------------------------------------------------------------- login

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type loginResponse struct {
	// Stage is "totp" (enter a code) or "enroll" (scan, then enter a code).
	Stage      string `json:"stage"`
	OTPAuthURI string `json:"otpauth_uri,omitempty"`
	Secret     string `json:"secret,omitempty"`
	Issuer     string `json:"issuer,omitempty"`
	Account    string `json:"account,omitempty"`
}

// Login is step one: email + password. It never issues a session — the only
// thing that does is a verified TOTP code. On first login it mints a candidate
// secret and hands back the otpauth URI for the QR code; that secret is not
// stored on the account until a code proves the phone has it.
func (a *API) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	email := strings.ToLower(strings.TrimSpace(req.Email))
	ip := clientIP(r)

	limited, err := a.rateLimited(r.Context(), email, ip)
	if err != nil {
		fail(w, "rate limit", err)
		return
	}
	if limited {
		a.recordAttempt(r.Context(), email, ip, false, "rate_limited")
		writeErr(w, http.StatusTooManyRequests, "rate_limited",
			"Too many failed attempts. Wait 15 minutes and try again.")
		return
	}

	var (
		id       string
		hash     string
		secret   *string
		enrolled *time.Time
	)
	err = a.DB.QueryRow(r.Context(), `
		select id::text, password_hash, totp_secret, totp_enrolled_at
		  from admin.admin_users
		 where email = $1 and disabled_at is null`, email).
		Scan(&id, &hash, &secret, &enrolled)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		// Spend roughly the same time as a real verify so the response time
		// does not answer "does this address have an account?".
		adminauth.VerifyPassword("$2a$12$UGAJ4XyO3sYcRC1qkpGSuOgc8lNI7Ux1MPWZ2Q3Zt.OSNqTKO8bqK", req.Password)
		a.recordAttempt(r.Context(), email, ip, false, "unknown_email")
		writeErr(w, http.StatusUnauthorized, "bad_credentials", "Email or password is incorrect.")
		return
	case err != nil:
		fail(w, "load admin", err)
		return
	}
	if !adminauth.VerifyPassword(hash, req.Password) {
		a.recordAttempt(r.Context(), email, ip, false, "bad_password")
		writeErr(w, http.StatusUnauthorized, "bad_credentials", "Email or password is incorrect.")
		return
	}

	resp := loginResponse{Stage: "totp"}
	var candidate *string
	if enrolled == nil || secret == nil || *secret == "" {
		fresh, err := adminauth.NewTOTPSecret()
		if err != nil {
			fail(w, "mint totp secret", err)
			return
		}
		candidate = &fresh
		resp = loginResponse{
			Stage:      "enroll",
			Secret:     fresh,
			OTPAuthURI: adminauth.OTPAuthURI(a.TOTPIssuer, email, fresh),
			Issuer:     a.TOTPIssuer,
			Account:    email,
		}
	}

	token, tokenHash, err := adminauth.NewToken()
	if err != nil {
		fail(w, "mint challenge", err)
		return
	}
	if _, err := a.DB.Exec(r.Context(), `
		insert into admin.login_challenges (token_hash, admin_user_id, secret_candidate, expires_at)
		values ($1, $2, $3, $4)`,
		tokenHash, id, candidate, a.now().Add(challengeTTL)); err != nil {
		fail(w, "store challenge", err)
		return
	}
	a.setCookie(w, challengeCookie, token, challengeTTL)
	writeJSON(w, http.StatusOK, resp)
}

type totpRequest struct {
	Code string `json:"code"`
}

// VerifyTOTP is step two. A correct code either confirms the enrollment
// candidate (writing it to the account) or matches the stored secret; either
// way the challenge is consumed and a session cookie is issued.
func (a *API) VerifyTOTP(w http.ResponseWriter, r *http.Request) {
	var req totpRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	c, err := r.Cookie(challengeCookie)
	if err != nil || c.Value == "" {
		writeErr(w, http.StatusUnauthorized, "no_challenge", "Start again from the sign-in screen.")
		return
	}
	tokenHash := adminauth.HashToken(c.Value)

	tx, err := a.DB.Begin(r.Context())
	if err != nil {
		fail(w, "begin totp tx", err)
		return
	}
	defer func() { _ = tx.Rollback(r.Context()) }()

	var (
		challengeID string
		adminID     string
		email       string
		candidate   *string
		stored      *string
		attempts    int
	)
	err = tx.QueryRow(r.Context(), `
		select c.id::text, u.id::text, u.email, c.secret_candidate, u.totp_secret, c.attempts
		  from admin.login_challenges c
		  join admin.admin_users u on u.id = c.admin_user_id
		 where c.token_hash = $1 and c.expires_at > now() and u.disabled_at is null
		 for update of c`, tokenHash).
		Scan(&challengeID, &adminID, &email, &candidate, &stored, &attempts)
	if errors.Is(err, pgx.ErrNoRows) {
		a.clearCookie(w, challengeCookie)
		writeErr(w, http.StatusUnauthorized, "no_challenge", "That sign-in attempt expired. Start again.")
		return
	}
	if err != nil {
		fail(w, "load challenge", err)
		return
	}
	if attempts >= maxChallengeAttempts {
		_, _ = tx.Exec(r.Context(), `delete from admin.login_challenges where id = $1`, challengeID)
		_ = tx.Commit(r.Context())
		a.clearCookie(w, challengeCookie)
		a.recordAttempt(context.WithoutCancel(r.Context()), email, clientIP(r), false, "totp_exhausted")
		writeErr(w, http.StatusTooManyRequests, "totp_exhausted",
			"Too many wrong codes. Sign in with your password again.")
		return
	}

	secret := ""
	enrolling := false
	if candidate != nil && *candidate != "" {
		secret, enrolling = *candidate, true
	} else if stored != nil {
		secret = *stored
	}
	if secret == "" || !adminauth.VerifyTOTP(secret, req.Code, a.now()) {
		if _, err := tx.Exec(r.Context(),
			`update admin.login_challenges set attempts = attempts + 1 where id = $1`,
			challengeID); err != nil {
			fail(w, "bump attempts", err)
			return
		}
		if err := tx.Commit(r.Context()); err != nil {
			fail(w, "commit attempts", err)
			return
		}
		a.recordAttempt(context.WithoutCancel(r.Context()), email, clientIP(r), false, "bad_totp")
		writeErr(w, http.StatusUnauthorized, "bad_totp", "That code is not right. Try the next one.")
		return
	}

	if enrolling {
		if _, err := tx.Exec(r.Context(), `
			update admin.admin_users
			   set totp_secret = $2, totp_enrolled_at = now()
			 where id = $1`, adminID, secret); err != nil {
			fail(w, "save totp secret", err)
			return
		}
	}
	if _, err := tx.Exec(r.Context(),
		`delete from admin.login_challenges where id = $1`, challengeID); err != nil {
		fail(w, "consume challenge", err)
		return
	}

	sessionToken, sessionHash, err := adminauth.NewToken()
	if err != nil {
		fail(w, "mint session", err)
		return
	}
	expires := a.now().Add(a.SessionTTL)
	if _, err := tx.Exec(r.Context(), `
		insert into admin.sessions (token_hash, admin_user_id, ip, user_agent, expires_at)
		values ($1, $2, $3, $4, $5)`,
		sessionHash, adminID, clientIP(r), truncate(r.UserAgent(), 400), expires); err != nil {
		fail(w, "store session", err)
		return
	}
	if _, err := tx.Exec(r.Context(),
		`update admin.admin_users set last_login_at = now() where id = $1`, adminID); err != nil {
		fail(w, "stamp login", err)
		return
	}
	// Expired and revoked sessions are dead weight; a login is a natural,
	// contention-free moment to sweep them.
	_, _ = tx.Exec(r.Context(),
		`delete from admin.sessions where expires_at < now() - interval '7 days'`)
	_, _ = tx.Exec(r.Context(),
		`delete from admin.login_challenges where expires_at < now()`)

	if err := tx.Commit(r.Context()); err != nil {
		fail(w, "commit login", err)
		return
	}
	a.recordAttempt(context.WithoutCancel(r.Context()), email, clientIP(r), true, "")
	a.clearCookie(w, challengeCookie)
	a.setCookie(w, sessionCookie, sessionToken, a.SessionTTL)

	var role string
	_ = a.DB.QueryRow(r.Context(), `select role from admin.admin_users where id = $1`, adminID).Scan(&role)
	writeJSON(w, http.StatusOK, map[string]any{
		"admin": Admin{ID: adminID, Email: email, Role: role, MFA: true,
			Expiry: expires.UTC().Format(time.RFC3339)},
	})
}

// Logout revokes the row behind the cookie — signing out on a shared laptop
// must invalidate the token, not merely forget it locally.
func (a *API) Logout(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie(sessionCookie); err == nil && c.Value != "" {
		_, _ = a.DB.Exec(r.Context(),
			`update admin.sessions set revoked_at = now()
			  where token_hash = $1 and revoked_at is null`,
			adminauth.HashToken(c.Value))
	}
	a.clearCookie(w, sessionCookie)
	a.clearCookie(w, challengeCookie)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// Me is what the SPA calls on boot to decide between the login screen and the
// console.
func (a *API) Me(w http.ResponseWriter, r *http.Request) {
	adm, _ := adminFrom(r.Context())
	writeJSON(w, http.StatusOK, map[string]any{"admin": adm})
}

type changePasswordRequest struct {
	Current string `json:"current_password"`
	New     string `json:"new_password"`
}

// ChangePassword rotates the caller's own password and revokes every other
// session they hold — a password change that leaves old cookies alive is not a
// password change.
func (a *API) ChangePassword(w http.ResponseWriter, r *http.Request) {
	adm, _ := adminFrom(r.Context())
	var req changePasswordRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	var hash string
	if err := a.DB.QueryRow(r.Context(),
		`select password_hash from admin.admin_users where id = $1`, adm.ID).Scan(&hash); err != nil {
		fail(w, "load password", err)
		return
	}
	if !adminauth.VerifyPassword(hash, req.Current) {
		writeErr(w, http.StatusUnauthorized, "bad_credentials", "Your current password is not right.")
		return
	}
	next, err := adminauth.HashPassword(req.New)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "weak_password", err.Error())
		return
	}
	current := ""
	if c, cerr := r.Cookie(sessionCookie); cerr == nil {
		current = adminauth.HashToken(c.Value)
	}
	if _, err := a.DB.Exec(r.Context(),
		`update admin.admin_users set password_hash = $2 where id = $1`, adm.ID, next); err != nil {
		fail(w, "save password", err)
		return
	}
	if _, err := a.DB.Exec(r.Context(),
		`update admin.sessions set revoked_at = now()
		  where admin_user_id = $1 and revoked_at is null and token_hash <> $2`,
		adm.ID, current); err != nil {
		fail(w, "revoke sessions", err)
		return
	}
	a.audit(r, auditEntry{Action: "admin.password.change", TargetType: "admin_user",
		TargetID: adm.ID, Summary: "Changed own password"})
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// ---------------------------------------------------------------- limiter

func (a *API) rateLimited(ctx context.Context, email, ip string) (bool, error) {
	var byEmail, byIP int
	err := a.DB.QueryRow(ctx, `
		select
		  count(*) filter (where email = $1),
		  count(*) filter (where ip = $2)
		from admin.login_attempts
		where ok = false and created_at > now() - $3::interval`,
		email, ip, loginWindow.String()).Scan(&byEmail, &byIP)
	if err != nil {
		return false, err
	}
	return byEmail >= maxFailsPerEmail || byIP >= maxFailsPerIP, nil
}

func (a *API) recordAttempt(ctx context.Context, email, ip string, ok bool, reason string) {
	var r *string
	if reason != "" {
		r = &reason
	}
	if _, err := a.DB.Exec(ctx,
		`insert into admin.login_attempts (email, ip, ok, reason) values ($1, $2, $3, $4)`,
		email, ip, ok, r); err != nil {
		slog.Warn("record login attempt", "err", err)
	}
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
