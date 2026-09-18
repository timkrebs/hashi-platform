// Package auth issues and describes JSON Web Tokens.
//
// There is no JWT library here on purpose: a JWT is three base64url segments
// joined by dots, and seeing that is worth more in an example than the
// convenience of a dependency.
package auth

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"
)

// Claims is the token payload. Field names are the registered JWT claims;
// anything custom belongs under a namespaced key, never a bare word a future
// registered claim might collide with.
type Claims struct {
	Issuer    string   `json:"iss"`
	Subject   string   `json:"sub"`
	Audience  string   `json:"aud"`
	ExpiresAt int64    `json:"exp"`
	IssuedAt  int64    `json:"iat"`
	NotBefore int64    `json:"nbf"`
	JWTID     string   `json:"jti"`
	Scopes    []string `json:"scope,omitempty"`
}

type header struct {
	Algorithm string `json:"alg"`
	Type      string `json:"typ"`
	KeyID     string `json:"kid"`
}

// encode builds and signs the token.
//
// The signature covers exactly header.payload -- the same bytes a verifier
// reconstructs. Signing anything else is the classic JWT bug: it verifies in
// your own tests and nowhere else.
func encode(key *rsa.PrivateKey, keyID string, c Claims) (string, error) {
	payload, err := json.Marshal(c)
	if err != nil {
		return "", fmt.Errorf("encode claims: %w", err)
	}
	h, err := json.Marshal(header{Algorithm: "RS256", Type: "JWT", KeyID: keyID})
	if err != nil {
		return "", fmt.Errorf("encode header: %w", err)
	}

	signingInput := b64(h) + "." + b64(payload)
	sum := sha256.Sum256([]byte(signingInput))

	// PKCS#1 v1.5, not PSS: RS256 is defined as PKCS#1 v1.5. PSS is PS256 and
	// every verifier expecting RS256 rejects it.
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, sum[:])
	if err != nil {
		return "", fmt.Errorf("sign: %w", err)
	}
	return signingInput + "." + b64(sig), nil
}

func b64(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

func newClaims(issuer, audience, subject, jti string, ttl time.Duration, now time.Time, scopes []string) Claims {
	return Claims{
		Issuer:   issuer,
		Subject:  subject,
		Audience: audience,
		// A second of leeway on nbf absorbs clock skew between pods; without it
		// a verifier whose clock is a fraction behind rejects a fresh token as
		// "not yet valid".
		NotBefore: now.Add(-time.Second).Unix(),
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(ttl).Unix(),
		JWTID:     jti,
		Scopes:    scopes,
	}
}
