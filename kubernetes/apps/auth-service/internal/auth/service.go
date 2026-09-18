package auth

import (
	"crypto/rand"
	"crypto/rsa"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/timkrebs/auth-service/internal/observability"
	"github.com/timkrebs/auth-service/internal/secrets"
)

// KeySource supplies the signing key and its id, or an error while the
// operator has not written the Secret yet.
type KeySource interface {
	Signing() (*rsa.PrivateKey, string, error)
}

// Verifier checks a username and password.
type Verifier interface {
	Verify(username, password string) error
}

type Options struct {
	Issuer   string
	Audience string
	TokenTTL time.Duration
}

// Service issues tokens and publishes the key needed to verify them.
//
// Nothing in here talks to Vault. The key and the user list were put on disk by
// the Vault Secrets Operator before this process started, so a Vault outage
// does not stop logins.
type Service struct {
	keys     KeySource
	verifier Verifier
	opts     Options
}

func NewService(keys KeySource, verifier Verifier, opts Options) *Service {
	return &Service{keys: keys, verifier: verifier, opts: opts}
}

// ErrInvalidCredentials is returned for a wrong username or password. The two
// are deliberately indistinguishable: separating them turns the endpoint into
// a username oracle.
var ErrInvalidCredentials = errors.New("invalid credentials")

// Issue verifies credentials and returns a signed token.
func (s *Service) Issue(username, password string, scopes []string) (string, time.Time, error) {
	if err := s.verifier.Verify(username, password); err != nil {
		if errors.Is(err, secrets.ErrInvalidCredentials) || errors.Is(err, ErrInvalidCredentials) {
			observability.TokensIssued.WithLabelValues("denied").Inc()
			return "", time.Time{}, ErrInvalidCredentials
		}
		// Anything else is this service failing, not the caller being wrong.
		observability.TokensIssued.WithLabelValues("error").Inc()
		return "", time.Time{}, fmt.Errorf("verify credentials: %w", err)
	}

	jti, err := newJTI()
	if err != nil {
		observability.TokensIssued.WithLabelValues("error").Inc()
		return "", time.Time{}, err
	}

	now := time.Now().UTC()
	claims := newClaims(s.opts.Issuer, s.opts.Audience, username, jti, s.opts.TokenTTL, now, scopes)

	key, keyID, err := s.keys.Signing()
	if err != nil {
		observability.TokensIssued.WithLabelValues("error").Inc()
		return "", time.Time{}, err
	}

	token, err := encode(key, keyID, claims)
	if err != nil {
		observability.TokensIssued.WithLabelValues("error").Inc()
		return "", time.Time{}, err
	}

	observability.TokensIssued.WithLabelValues("ok").Inc()
	return token, time.Unix(claims.ExpiresAt, 0).UTC(), nil
}

// JWK is one entry of the JWKS document.
type JWK struct {
	Kty string `json:"kty"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	Kid string `json:"kid"`
	N   string `json:"n"`
	E   string `json:"e"`
}

// JWKS returns the public key.
//
// This is what keeps the architecture from having a single point of failure:
// every other service verifies tokens locally against this document and never
// calls the auth service on the request path.
//
// One key, because the pod holds one. A rotation replaces the Secret and the
// operator restarts this Deployment, so the new pod publishes the new key under
// a new kid. Tokens signed by the old key stop verifying at that moment, which
// is why the TTL is short -- if that matters, publish the previous key here too
// for one TTL's worth of overlap.
func (s *Service) JWKS() ([]JWK, error) {
	key, keyID, err := s.keys.Signing()
	if err != nil {
		return nil, err
	}
	pub := &key.PublicKey
	return []JWK{{
		Kty: "RSA",
		Use: "sig",
		Alg: "RS256",
		Kid: keyID,
		N:   secrets.Base64URL(pub.N.Bytes()),
		E:   secrets.Base64URL(secrets.ExponentBytes(pub.E)),
	}}, nil
}

func newJTI() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate token id: %w", err)
	}
	return hex.EncodeToString(b), nil
}
