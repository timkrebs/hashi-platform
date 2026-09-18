// Package auth issues and describes JSON Web Tokens.
//
// There is no JWT library here on purpose. The signature comes from Vault, so a
// library would only be assembling base64 segments -- and a JWT is clearer when
// you can see that it is three base64url strings joined by dots.
package auth

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strconv"
	"time"
)

// Claims is the token payload. Field names are the registered JWT claims;
// anything custom belongs under a namespaced key, never a bare word that a
// future registered claim might collide with.
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

// Signer is what auth needs from Vault. An interface, so the tests run without
// a Vault.
type Signer interface {
	Sign(ctx context.Context, mount, key string, data []byte) ([]byte, int, error)
}

// encode builds the JWT and reports which key version actually signed it.
//
// kid has to be inside the header, and the header is part of the signing input,
// so the key version must be known before signing -- it is passed in from the
// cached JWKS rather than discovered with an extra Vault round trip, because
// this is the critical path of every login.
//
// Sign also returns the version it used. If the key rotated between the cache
// being filled and the call landing, the returned version differs from the one
// in the header, and the caller has to rebuild -- a token whose kid does not
// match its signature fails verification in a way that is very hard to read.
func encode(ctx context.Context, s Signer, mount, key string, version int, c Claims) (string, int, error) {
	payload, err := json.Marshal(c)
	if err != nil {
		return "", 0, fmt.Errorf("encode claims: %w", err)
	}

	h, err := json.Marshal(header{Algorithm: "RS256", Type: "JWT", KeyID: strconv.Itoa(version)})
	if err != nil {
		return "", 0, fmt.Errorf("encode header: %w", err)
	}

	signingInput := b64(h) + "." + b64(payload)
	sig, signedWith, err := s.Sign(ctx, mount, key, []byte(signingInput))
	if err != nil {
		return "", 0, err
	}

	return signingInput + "." + b64(sig), signedWith, nil
}

func b64(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

func newClaims(issuer, audience, subject, jti string, ttl time.Duration, now time.Time, scopes []string) Claims {
	return Claims{
		Issuer:   issuer,
		Subject:  subject,
		Audience: audience,
		// One second of leeway on nbf absorbs clock skew between pods. Without
		// it a token can be rejected as "not yet valid" by a verifier whose
		// clock is a fraction behind.
		NotBefore: now.Add(-time.Second).Unix(),
		IssuedAt:  now.Unix(),
		ExpiresAt: now.Add(ttl).Unix(),
		JWTID:     jti,
		Scopes:    scopes,
	}
}
