package adminauth

import (
	"strings"
	"testing"
	"time"
)

// RFC 6238 Appendix B, SHA-1 rows. The published vectors are 8 digits; Even
// uses 6, which is the same truncation modulo 10^6 — so the expected values
// here are the last six digits of the published ones. Pinning these means a
// refactor of the HMAC/truncation path cannot quietly produce codes that no
// authenticator app agrees with.
func TestTOTPCodeMatchesRFC6238(t *testing.T) {
	// "12345678901234567890" in base32.
	const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
	cases := []struct {
		unix int64
		want string
	}{
		{59, "287082"},         // published 94287082
		{1111111109, "081804"}, // published 07081804
		{1111111111, "050471"}, // published 14050471
		{1234567890, "005924"}, // published 89005924
		{2000000000, "279037"}, // published 69279037
	}
	for _, c := range cases {
		got, err := TOTPCode(secret, time.Unix(c.unix, 0))
		if err != nil {
			t.Fatalf("TOTPCode(%d): %v", c.unix, err)
		}
		if got != c.want {
			t.Errorf("TOTPCode at %d = %q, want %q", c.unix, got, c.want)
		}
	}
}

func TestTOTPCodeRejectsNonBase32(t *testing.T) {
	if _, err := TOTPCode("not-base-32!", time.Unix(59, 0)); err == nil {
		t.Fatal("expected an error for a secret that is not base32")
	}
}

// A phone whose clock is a step out must still get in; a code two steps out
// must not. This is the whole reason TOTPSkew exists, and widening it is a
// security change that should break a test.
func TestVerifyTOTPAcceptsOneStepOfDrift(t *testing.T) {
	const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
	now := time.Unix(1234567890, 0)

	for _, offset := range []time.Duration{-TOTPPeriod, 0, TOTPPeriod} {
		code, err := TOTPCode(secret, now.Add(offset))
		if err != nil {
			t.Fatal(err)
		}
		if !VerifyTOTP(secret, code, now) {
			t.Errorf("code from offset %v should verify", offset)
		}
	}
	for _, offset := range []time.Duration{-2 * TOTPPeriod, 2 * TOTPPeriod} {
		code, err := TOTPCode(secret, now.Add(offset))
		if err != nil {
			t.Fatal(err)
		}
		if VerifyTOTP(secret, code, now) {
			t.Errorf("code from offset %v must NOT verify — skew is one step", offset)
		}
	}
}

func TestVerifyTOTPRejectsMalformedInput(t *testing.T) {
	const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
	now := time.Unix(1234567890, 0)
	for _, code := range []string{"", "12345", "1234567", "abcdef", "00592"} {
		if VerifyTOTP(secret, code, now) {
			t.Errorf("VerifyTOTP accepted %q", code)
		}
	}
	// An empty secret must never verify anything, however well-formed the code.
	if VerifyTOTP("", "005924", now) {
		t.Error("VerifyTOTP accepted a code against an empty secret")
	}
}

// Whitespace around a pasted code is the single most common way a correct code
// gets rejected. It is trimmed on purpose.
func TestVerifyTOTPTrimsWhitespace(t *testing.T) {
	const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
	now := time.Unix(1234567890, 0)
	if !VerifyTOTP(secret, "  005924 ", now) {
		t.Error("a padded code should verify")
	}
}

func TestNewTOTPSecretIsUsableAndUnique(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 32; i++ {
		s, err := NewTOTPSecret()
		if err != nil {
			t.Fatal(err)
		}
		if len(s) != 32 { // 20 bytes, base32, unpadded
			t.Fatalf("secret %q has length %d, want 32", s, len(s))
		}
		if seen[s] {
			t.Fatalf("NewTOTPSecret repeated %q", s)
		}
		seen[s] = true
		if _, err := TOTPCode(s, time.Now()); err != nil {
			t.Fatalf("fresh secret does not produce a code: %v", err)
		}
	}
}

func TestOTPAuthURICarriesEverythingAnAppNeeds(t *testing.T) {
	uri := OTPAuthURI("Even Admin", "ops@example.com", "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
	for _, want := range []string{
		"otpauth://totp/",
		"secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
		"issuer=Even+Admin",
		"algorithm=SHA1",
		"digits=6",
		"period=30",
	} {
		if !strings.Contains(uri, want) {
			t.Errorf("otpauth URI %q is missing %q", uri, want)
		}
	}
}

// ---------------------------------------------------------------- password

func TestHashPasswordRoundTrips(t *testing.T) {
	const plain = "correct-horse-9!"
	hash, err := HashPassword(plain)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(hash, plain) {
		t.Fatal("the hash contains the plaintext")
	}
	if !VerifyPassword(hash, plain) {
		t.Error("the password should verify against its own hash")
	}
	if VerifyPassword(hash, plain+"x") {
		t.Error("a different password must not verify")
	}
	if VerifyPassword("not-a-bcrypt-hash", plain) {
		t.Error("a malformed hash must not verify")
	}
}

// Two hashes of the same password must differ — bcrypt salts each one. If this
// ever fails the salt has been fixed, and the whole table is rainbow-able.
func TestHashPasswordIsSalted(t *testing.T) {
	a, err := HashPassword("correct-horse-9!")
	if err != nil {
		t.Fatal(err)
	}
	b, err := HashPassword("correct-horse-9!")
	if err != nil {
		t.Fatal(err)
	}
	if a == b {
		t.Fatal("two hashes of the same password are identical — the salt is not random")
	}
}

func TestCheckPasswordStrength(t *testing.T) {
	ok := []string{"correct-horse-9!", "a-very-long-passphrase-1", "Xy9!Xy9!Xy9!"}
	bad := []string{"", "short1!", "aaaaaaaaaaaa", "123456789012", "-----------!"}
	for _, p := range ok {
		if err := CheckPasswordStrength(p); err != nil {
			t.Errorf("CheckPasswordStrength(%q) = %v, want nil", p, err)
		}
	}
	for _, p := range bad {
		if err := CheckPasswordStrength(p); err == nil {
			t.Errorf("CheckPasswordStrength(%q) = nil, want an error", p)
		}
	}
}

func TestHashPasswordRefusesWeakInput(t *testing.T) {
	if _, err := HashPassword("short1!"); err == nil {
		t.Fatal("HashPassword accepted a password the strength check rejects")
	}
}

// ---------------------------------------------------------------- tokens

func TestNewTokenIsRandomAndHashesStably(t *testing.T) {
	seen := map[string]bool{}
	for i := 0; i < 64; i++ {
		token, hash, err := NewToken()
		if err != nil {
			t.Fatal(err)
		}
		if seen[token] {
			t.Fatalf("NewToken repeated %q", token)
		}
		seen[token] = true
		if len(token) < 40 {
			t.Fatalf("token %q is shorter than 256 bits of entropy would be", token)
		}
		if hash == token {
			t.Fatal("the stored hash equals the cookie value — a database dump would be replayable")
		}
		if got := HashToken(token); got != hash {
			t.Fatalf("HashToken is not stable: %q vs %q", got, hash)
		}
	}
}

func TestHashTokenTrimsWhitespace(t *testing.T) {
	if HashToken(" abc ") != HashToken("abc") {
		t.Error("HashToken should ignore surrounding whitespace")
	}
	if HashToken("abc") == HashToken("abd") {
		t.Error("different tokens must hash differently")
	}
}
