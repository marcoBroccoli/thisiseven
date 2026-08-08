// Package adminauth holds the console's own identity: password hashing, TOTP,
// session tokens and the login rate limiter. It knows nothing about product
// data — an admin is not an Even user and never becomes one.
package adminauth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/subtle"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strings"
	"time"
)

// TOTPPeriod and TOTPDigits are the RFC 6238 defaults every authenticator app
// assumes when the otpauth URI omits them.
const (
	TOTPPeriod = 30 * time.Second
	TOTPDigits = 6
	// TOTPSkew accepts the step before and after the current one, so a phone
	// whose clock drifts by a few seconds still logs in.
	TOTPSkew = 1
)

var b32 = base32.StdEncoding.WithPadding(base32.NoPadding)

// NewTOTPSecret mints a 160-bit secret — the shared-secret size RFC 4226
// recommends for HMAC-SHA1, and what Google Authenticator expects.
func NewTOTPSecret() (string, error) {
	buf := make([]byte, 20)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return b32.EncodeToString(buf), nil
}

// OTPAuthURI is what the QR code encodes. The label carries the issuer twice
// (path prefix and parameter) because different apps read different ones.
func OTPAuthURI(issuer, account, secret string) string {
	label := url.PathEscape(issuer + ":" + account)
	q := url.Values{}
	q.Set("secret", secret)
	q.Set("issuer", issuer)
	q.Set("algorithm", "SHA1")
	q.Set("digits", fmt.Sprint(TOTPDigits))
	q.Set("period", fmt.Sprint(int(TOTPPeriod.Seconds())))
	return "otpauth://totp/" + label + "?" + q.Encode()
}

// TOTPCode computes the code for one counter step.
func TOTPCode(secret string, t time.Time) (string, error) {
	key, err := b32.DecodeString(strings.ToUpper(strings.TrimSpace(secret)))
	if err != nil {
		return "", fmt.Errorf("totp secret is not base32: %w", err)
	}
	counter := uint64(t.Unix()) / uint64(TOTPPeriod.Seconds())
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], counter)

	mac := hmac.New(sha1.New, key)
	mac.Write(msg[:])
	sum := mac.Sum(nil)

	offset := sum[len(sum)-1] & 0x0f
	trunc := binary.BigEndian.Uint32(sum[offset:offset+4]) & 0x7fffffff
	mod := uint32(1)
	for i := 0; i < TOTPDigits; i++ {
		mod *= 10
	}
	return fmt.Sprintf("%0*d", TOTPDigits, trunc%mod), nil
}

// VerifyTOTP checks a user-entered code against the secret, allowing one step
// of drift each way. Comparison is constant-time: a timing oracle on a 6-digit
// code is a real (if slow) way to walk the answer out of the server.
func VerifyTOTP(secret, code string, now time.Time) bool {
	code = strings.TrimSpace(code)
	if len(code) != TOTPDigits {
		return false
	}
	for skew := -TOTPSkew; skew <= TOTPSkew; skew++ {
		want, err := TOTPCode(secret, now.Add(time.Duration(skew)*TOTPPeriod))
		if err != nil {
			return false
		}
		if subtle.ConstantTimeCompare([]byte(want), []byte(code)) == 1 {
			return true
		}
	}
	return false
}
