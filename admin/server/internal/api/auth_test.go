package api

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/marcoBroccoli/thisiseven/admin/internal/adminauth"
)

// The password step must never be enough. This is the single most important
// property of the console's login, so it is asserted directly: after a correct
// password and before a code, /api/auth/me is still 401.
func TestPasswordAloneDoesNotOpenASession(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()

	res, body := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": testAdminEmail, "password": testAdminPassword})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("login status %d (%v)", res.StatusCode, body)
	}
	if body["stage"] != "enroll" {
		t.Fatalf("first login should ask for enrollment, got stage %v", body["stage"])
	}

	res, _ = h.do(http.MethodGet, "/api/auth/me", nil)
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("me after password only = %d, want 401", res.StatusCode)
	}
}

// First login mints a candidate secret and hands back a QR URI. The secret must
// not reach the account until a code proves the phone has it — otherwise an
// interrupted enrollment locks the operator out of their own console.
func TestEnrollmentSecretIsNotStoredUntilVerified(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()

	res, body := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": testAdminEmail, "password": testAdminPassword})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("login status %d", res.StatusCode)
	}
	secret, _ := body["secret"].(string)
	if secret == "" {
		t.Fatal("enrollment did not return a secret")
	}
	if uri, _ := body["otpauth_uri"].(string); uri == "" {
		t.Fatal("enrollment did not return an otpauth URI for the QR code")
	}

	var stored *string
	if err := h.db.QueryRow(context.Background(),
		`select totp_secret from admin.admin_users where email = $1`, testAdminEmail).
		Scan(&stored); err != nil {
		t.Fatalf("read account: %v", err)
	}
	if stored != nil {
		t.Fatal("the candidate secret was written to the account before a code confirmed it")
	}

	code, err := adminauth.TOTPCode(secret, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if res, body = h.do(http.MethodPost, "/api/auth/totp", map[string]string{"code": code}); res.StatusCode != http.StatusOK {
		t.Fatalf("totp status %d (%v)", res.StatusCode, body)
	}

	if err := h.db.QueryRow(context.Background(),
		`select totp_secret from admin.admin_users where email = $1`, testAdminEmail).
		Scan(&stored); err != nil {
		t.Fatalf("read account: %v", err)
	}
	if stored == nil || *stored != secret {
		t.Fatal("the verified secret was not persisted")
	}
}

func TestFullSignInThenMe(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	res, body := h.do(http.MethodGet, "/api/auth/me", nil)
	if res.StatusCode != http.StatusOK {
		t.Fatalf("me status %d (%v)", res.StatusCode, body)
	}
	admin, ok := body["admin"].(map[string]any)
	if !ok {
		t.Fatalf("me returned %v", body)
	}
	if admin["email"] != testAdminEmail {
		t.Errorf("me email = %v, want %s", admin["email"], testAdminEmail)
	}
	if admin["mfa_enrolled"] != true {
		t.Error("me should report MFA as enrolled after verifying a code")
	}
}

// A second login uses the stored secret and must NOT hand out a new one — an
// endpoint that re-issues a secret to anyone with the password is a bypass of
// the second factor.
func TestSecondLoginUsesTheStoredSecret(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()
	h.do(http.MethodPost, "/api/auth/logout", nil)

	res, body := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": testAdminEmail, "password": testAdminPassword})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("second login status %d", res.StatusCode)
	}
	if body["stage"] != "totp" {
		t.Errorf("second login stage = %v, want \"totp\"", body["stage"])
	}
	if s, _ := body["secret"].(string); s != "" {
		t.Error("a second login handed out a TOTP secret — that defeats the second factor")
	}
}

func TestUnknownEmailAndBadPasswordLookIdentical(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()

	resA, bodyA := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": "nobody@even.test", "password": testAdminPassword})
	resB, bodyB := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": testAdminEmail, "password": "wrong-password-here"})

	if resA.StatusCode != http.StatusUnauthorized || resB.StatusCode != http.StatusUnauthorized {
		t.Fatalf("statuses %d / %d, want 401 / 401", resA.StatusCode, resB.StatusCode)
	}
	// Same code and same message: the response must not answer "does this
	// address have an account?".
	if errCode(bodyA) != errCode(bodyB) {
		t.Errorf("error codes differ: %q vs %q", errCode(bodyA), errCode(bodyB))
	}
}

func TestWrongTOTPIsRejectedAndTheChallengeExhausts(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()

	if res, _ := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": testAdminEmail, "password": testAdminPassword}); res.StatusCode != http.StatusOK {
		t.Fatalf("login status %d", res.StatusCode)
	}

	// maxChallengeAttempts wrong codes are answered 401; the next one kills the
	// challenge so the 6-digit space cannot be walked inside one attempt.
	for i := 0; i < maxChallengeAttempts; i++ {
		res, body := h.do(http.MethodPost, "/api/auth/totp", map[string]string{"code": "000000"})
		if res.StatusCode != http.StatusUnauthorized {
			t.Fatalf("attempt %d: status %d (%v), want 401", i+1, res.StatusCode, body)
		}
	}
	res, body := h.do(http.MethodPost, "/api/auth/totp", map[string]string{"code": "000000"})
	if res.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("exhausted challenge status %d (%v), want 429", res.StatusCode, body)
	}
	if code := errCode(body); code != "totp_exhausted" {
		t.Errorf("error code = %q, want totp_exhausted", code)
	}
}

func TestTOTPWithoutAChallengeIsRejected(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()

	res, body := h.do(http.MethodPost, "/api/auth/totp", map[string]string{"code": "123456"})
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status %d, want 401", res.StatusCode)
	}
	if code := errCode(body); code != "no_challenge" {
		t.Errorf("error code = %q, want no_challenge", code)
	}
}

// The limiter reads admin.login_attempts, so seeding failures directly is a
// faithful way to reach the threshold without 8 round trips.
func TestLoginIsRateLimitedPerEmail(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()

	for i := 0; i < maxFailsPerEmail; i++ {
		if _, err := h.db.Exec(context.Background(),
			`insert into admin.login_attempts (email, ip, ok, reason)
			 values ($1, '203.0.113.9', false, 'bad_password')`, testAdminEmail); err != nil {
			t.Fatalf("seed attempt: %v", err)
		}
	}
	res, body := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": testAdminEmail, "password": testAdminPassword})
	if res.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("status %d (%v), want 429 — a correct password must not bypass the limiter",
			res.StatusCode, body)
	}
}

func TestLogoutRevokesTheSessionRow(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	if res, _ := h.do(http.MethodPost, "/api/auth/logout", nil); res.StatusCode != http.StatusOK {
		t.Fatalf("logout status %d", res.StatusCode)
	}
	var live int
	if err := h.db.QueryRow(context.Background(),
		`select count(*) from admin.sessions where revoked_at is null`).Scan(&live); err != nil {
		t.Fatal(err)
	}
	if live != 0 {
		t.Errorf("%d session rows are still live after signing out", live)
	}
	if res, _ := h.do(http.MethodGet, "/api/auth/me", nil); res.StatusCode != http.StatusUnauthorized {
		t.Errorf("me after logout = %d, want 401", res.StatusCode)
	}
}

// Forgetting a cookie is not revocation. A session revoked server-side must
// stop working even though the browser still presents it.
func TestRevokedSessionIsRejectedEvenWithTheCookie(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	if _, err := h.db.Exec(context.Background(),
		`update admin.sessions set revoked_at = now()`); err != nil {
		t.Fatal(err)
	}
	if res, _ := h.do(http.MethodGet, "/api/auth/me", nil); res.StatusCode != http.StatusUnauthorized {
		t.Errorf("me with a revoked session = %d, want 401", res.StatusCode)
	}
}

func TestExpiredSessionIsRejected(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	if _, err := h.db.Exec(context.Background(),
		`update admin.sessions set expires_at = now() - interval '1 minute'`); err != nil {
		t.Fatal(err)
	}
	if res, _ := h.do(http.MethodGet, "/api/auth/me", nil); res.StatusCode != http.StatusUnauthorized {
		t.Errorf("me with an expired session = %d, want 401", res.StatusCode)
	}
}

func TestDisabledAccountCannotSignIn(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	if _, err := h.db.Exec(context.Background(),
		`update admin.admin_users set disabled_at = now() where email = $1`, testAdminEmail); err != nil {
		t.Fatal(err)
	}
	res, _ := h.do(http.MethodPost, "/api/auth/login",
		map[string]string{"email": testAdminEmail, "password": testAdminPassword})
	if res.StatusCode != http.StatusUnauthorized {
		t.Errorf("disabled account login = %d, want 401", res.StatusCode)
	}
}

// Bootstrap is a first-boot seed, not a password reset. Leaving the env vars in
// place must not resurrect or overwrite anything.
func TestBootstrapOnlyRunsOnAnEmptyTable(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()

	var before string
	if err := h.db.QueryRow(context.Background(),
		`select password_hash from admin.admin_users where email = $1`, testAdminEmail).
		Scan(&before); err != nil {
		t.Fatal(err)
	}
	h.seedAdmin() // second call, table not empty

	var count int
	var after string
	if err := h.db.QueryRow(context.Background(),
		`select count(*) from admin.admin_users`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if err := h.db.QueryRow(context.Background(),
		`select password_hash from admin.admin_users where email = $1`, testAdminEmail).
		Scan(&after); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Errorf("admin_users has %d rows, want 1", count)
	}
	if before != after {
		t.Error("a second bootstrap rewrote the existing password hash")
	}
}

func TestChangePasswordRevokesOtherSessionsButNotThisOne(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	// A second, unrelated session for the same account.
	token, hash, err := adminauth.NewToken()
	if err != nil {
		t.Fatal(err)
	}
	_ = token
	if _, err := h.db.Exec(context.Background(), `
		insert into admin.sessions (token_hash, admin_user_id, expires_at)
		select $1, id, now() + interval '12 hours' from admin.admin_users where email = $2`,
		hash, testAdminEmail); err != nil {
		t.Fatal(err)
	}

	res, body := h.do(http.MethodPost, "/api/auth/password", map[string]string{
		"current_password": testAdminPassword,
		"new_password":     "a-brand-new-passphrase-1!",
	})
	if res.StatusCode != http.StatusOK {
		t.Fatalf("change password status %d (%v)", res.StatusCode, body)
	}
	// The caller keeps working…
	if res, _ := h.do(http.MethodGet, "/api/auth/me", nil); res.StatusCode != http.StatusOK {
		t.Errorf("own session died on password change: %d", res.StatusCode)
	}
	// …and the other one is gone.
	var live int
	if err := h.db.QueryRow(context.Background(),
		`select count(*) from admin.sessions where revoked_at is null`).Scan(&live); err != nil {
		t.Fatal(err)
	}
	if live != 1 {
		t.Errorf("%d live sessions after a password change, want 1 (only the caller's)", live)
	}
}

func TestChangePasswordRejectsAWrongCurrentPassword(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	res, _ := h.do(http.MethodPost, "/api/auth/password", map[string]string{
		"current_password": "not-the-password",
		"new_password":     "a-brand-new-passphrase-1!",
	})
	if res.StatusCode != http.StatusUnauthorized {
		t.Errorf("status %d, want 401", res.StatusCode)
	}
}

func TestChangePasswordRejectsAWeakNewPassword(t *testing.T) {
	h := newHarness(t)
	h.seedAdmin()
	h.signIn()

	res, _ := h.do(http.MethodPost, "/api/auth/password", map[string]string{
		"current_password": testAdminPassword,
		"new_password":     "short1!",
	})
	if res.StatusCode != http.StatusBadRequest {
		t.Errorf("status %d, want 400", res.StatusCode)
	}
}
