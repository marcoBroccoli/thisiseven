package auth

import (
	"fmt"

	"github.com/golang-jwt/jwt/v5"
)

// Verifier checks GoTrue-issued HS256 access tokens. evend never mints
// tokens — GoTrue is the only issuer in the stack.
type Verifier struct {
	secret []byte
}

func NewVerifier(secret []byte) *Verifier { return &Verifier{secret: secret} }

// VerifyAccess returns the GoTrue user id (sub) for a valid token.
func (v *Verifier) VerifyAccess(raw string) (string, error) {
	tok, err := jwt.Parse(raw,
		func(t *jwt.Token) (any, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method %v", t.Header["alg"])
			}
			return v.secret, nil
		},
		jwt.WithValidMethods([]string{"HS256"}),
		jwt.WithAudience("authenticated"),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return "", err
	}
	sub, err := tok.Claims.GetSubject()
	if err != nil || sub == "" {
		return "", fmt.Errorf("token has no subject")
	}
	return sub, nil
}
