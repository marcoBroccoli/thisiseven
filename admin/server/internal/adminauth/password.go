package adminauth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"strings"
	"unicode"

	"golang.org/x/crypto/bcrypt"
)

// BcryptCost is deliberately above bcrypt's default 10. The console has a
// handful of accounts and no login-throughput problem, so the extra ~4x work
// per attempt is free for us and expensive for anyone with the hash table.
const BcryptCost = 12

var ErrWeakPassword = errors.New("password must be at least 12 characters and mix letters with a digit or symbol")

func HashPassword(plain string) (string, error) {
	if err := CheckPasswordStrength(plain); err != nil {
		return "", err
	}
	h, err := bcrypt.GenerateFromPassword([]byte(plain), BcryptCost)
	return string(h), err
}

func VerifyPassword(hash, plain string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plain)) == nil
}

// CheckPasswordStrength is a floor, not a policy engine: length does most of
// the work, and the character rule only stops "aaaaaaaaaaaa".
func CheckPasswordStrength(plain string) error {
	if len([]rune(plain)) < 12 {
		return ErrWeakPassword
	}
	var letter, other bool
	for _, r := range plain {
		switch {
		case unicode.IsLetter(r):
			letter = true
		case unicode.IsDigit(r), unicode.IsPunct(r), unicode.IsSymbol(r):
			other = true
		}
	}
	if !letter || !other {
		return ErrWeakPassword
	}
	return nil
}

// NewToken returns the opaque value that goes in a cookie, plus the sha256 the
// database stores. The plaintext exists only in this process and the browser.
func NewToken() (token, hash string, err error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", "", err
	}
	token = base64.RawURLEncoding.EncodeToString(buf)
	return token, HashToken(token), nil
}

func HashToken(token string) string {
	sum := sha256.Sum256([]byte(strings.TrimSpace(token)))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}
