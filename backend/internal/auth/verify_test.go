package auth

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func mint(t *testing.T, secret []byte, claims jwt.MapClaims) string {
	t.Helper()
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	s, err := tok.SignedString(secret)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestVerifyAccess(t *testing.T) {
	secret := []byte("test-secret")
	v := NewVerifier(secret)

	good := mint(t, secret, jwt.MapClaims{
		"sub": "3f5f3b9e-3c1a-4bfa-9df8-3f2f45f0a111",
		"aud": "authenticated",
		"exp": time.Now().Add(time.Hour).Unix(),
	})
	sub, err := v.VerifyAccess(good)
	if err != nil || sub != "3f5f3b9e-3c1a-4bfa-9df8-3f2f45f0a111" {
		t.Fatalf("want valid, got sub=%q err=%v", sub, err)
	}

	expired := mint(t, secret, jwt.MapClaims{
		"sub": "u", "aud": "authenticated", "exp": time.Now().Add(-time.Minute).Unix(),
	})
	if _, err := v.VerifyAccess(expired); err == nil {
		t.Fatal("expired token accepted")
	}

	forged := mint(t, []byte("wrong-secret"), jwt.MapClaims{
		"sub": "u", "aud": "authenticated", "exp": time.Now().Add(time.Hour).Unix(),
	})
	if _, err := v.VerifyAccess(forged); err == nil {
		t.Fatal("forged token accepted")
	}

	wrongAud := mint(t, secret, jwt.MapClaims{
		"sub": "u", "aud": "anon", "exp": time.Now().Add(time.Hour).Unix(),
	})
	if _, err := v.VerifyAccess(wrongAud); err == nil {
		t.Fatal("wrong-audience token accepted")
	}

	noExp := mint(t, secret, jwt.MapClaims{"sub": "u", "aud": "authenticated"})
	if _, err := v.VerifyAccess(noExp); err == nil {
		t.Fatal("no-expiry token accepted")
	}
}
