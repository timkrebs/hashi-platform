package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"strconv"
	"sync"
	"time"

	"github.com/timkrebs/auth-service/internal/observability"
)

// Verifier checks credentials. Vault's userpass implements it.
type Verifier interface {
	VerifyUserpass(ctx context.Context, mount, username, password string) error
}

// KeyReader exposes the public halves of the signing key.
type KeyReader interface {
	PublicKeys(ctx context.Context, mount, key string) (map[int]*rsa.PublicKey, int, error)
}

type Options struct {
	TransitMount  string
	SigningKey    string
	UserpassMount string
	Issuer        string
	Audience      string
	TokenTTL      time.Duration
}

// Service issues tokens and publishes the keys needed to verify them.
type Service struct {
	signer   Signer
	verifier Verifier
	keys     KeyReader
	opts     Options

	mu            sync.RWMutex
	cachedJWKS    []JWK
	cachedAt      time.Time
	latestVersion int
}

func NewService(signer Signer, verifier Verifier, keys KeyReader, opts Options) *Service {
	return &Service{signer: signer, verifier: verifier, keys: keys, opts: opts}
}

// ErrInvalidCredentials is returned for a wrong username or password. It is
// deliberately indistinguishable between the two cases: telling them apart
// turns the endpoint into a username oracle.
var ErrInvalidCredentials = fmt.Errorf("invalid credentials")

// Issue verifies credentials and returns a signed token.
func (s *Service) Issue(ctx context.Context, username, password string, scopes []string) (string, time.Time, error) {
	if err := s.verifier.VerifyUserpass(ctx, s.opts.UserpassMount, username, password); err != nil {
		// Only a 4xx means the credentials were actually rejected. A refused
		// connection or a 5xx means Vault could not answer -- reporting that as
		// "invalid username or password" sends every user and every operator
		// looking for a credentials problem during a Vault outage.
		if isRejection(err) {
			observability.TokensIssued.WithLabelValues("denied").Inc()
			return "", time.Time{}, ErrInvalidCredentials
		}
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

	s.mu.RLock()
	version := s.latestVersion
	s.mu.RUnlock()

	token, signedWith, err := encode(ctx, s.signer, s.opts.TransitMount, s.opts.SigningKey, version, claims)
	if err != nil {
		observability.TokensIssued.WithLabelValues("error").Inc()
		return "", time.Time{}, err
	}

	if signedWith != version {
		// The key rotated since the cache was filled. Rebuild with the version
		// that actually signed, and drop the cache so JWKS picks up the new one.
		s.mu.Lock()
		s.latestVersion, s.cachedJWKS = signedWith, nil
		s.mu.Unlock()

		token, _, err = encode(ctx, s.signer, s.opts.TransitMount, s.opts.SigningKey, signedWith, claims)
		if err != nil {
			observability.TokensIssued.WithLabelValues("error").Inc()
			return "", time.Time{}, err
		}
	}

	observability.TokensIssued.WithLabelValues("ok").Inc()
	return token, time.Unix(claims.ExpiresAt, 0).UTC(), nil
}

// isRejection reports whether the error carries a 4xx status, which is how the
// verifier says "these credentials are wrong" as opposed to "I am broken".
//
// Checked through an interface rather than a concrete type so this package
// stays independent of the Vault client.
func isRejection(err error) bool {
	var se interface{ StatusCode() int }
	if !errors.As(err, &se) {
		return false
	}
	code := se.StatusCode()
	return code >= 400 && code < 500
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

// JWKS returns the public keys, cached for a minute.
//
// Publishing every version, not only the current one, is what makes key
// rotation non-disruptive: tokens signed before the rotation stay verifiable
// until they expire.
func (s *Service) JWKS(ctx context.Context) ([]JWK, error) {
	s.mu.RLock()
	if time.Since(s.cachedAt) < time.Minute && s.cachedJWKS != nil {
		defer s.mu.RUnlock()
		return s.cachedJWKS, nil
	}
	s.mu.RUnlock()

	return s.refreshKeys(ctx)
}

// refreshKeys always goes to Vault, bypassing the cache.
func (s *Service) refreshKeys(ctx context.Context) ([]JWK, error) {
	keys, latest, err := s.keys.PublicKeys(ctx, s.opts.TransitMount, s.opts.SigningKey)
	if err != nil {
		return nil, err
	}

	out := make([]JWK, 0, len(keys))
	for version, pub := range keys {
		out = append(out, JWK{
			Kty: "RSA",
			Use: "sig",
			Alg: "RS256",
			Kid: strconv.Itoa(version),
			N:   base64.RawURLEncoding.EncodeToString(pub.N.Bytes()),
			E:   encodeExponent(pub.E),
		})
	}

	s.mu.Lock()
	s.cachedJWKS, s.cachedAt, s.latestVersion = out, time.Now(), latest
	s.mu.Unlock()
	return out, nil
}

// Warm fetches the keys from Vault, bypassing the cache.
//
// It is both the startup check and the periodic readiness probe, so it must not
// read the cache: a cached answer would report Vault as healthy long after it
// stopped responding, and the pod would keep taking traffic it cannot serve.
func (s *Service) Warm(ctx context.Context) error {
	_, err := s.refreshKeys(ctx)
	return err
}

func encodeExponent(e int) string {
	// JWKS wants the exponent as a minimal big-endian byte string, base64url
	// encoded -- for the usual 65537 that is "AQAB".
	return base64.RawURLEncoding.EncodeToString(new(big.Int).SetInt64(int64(e)).Bytes())
}

func newJTI() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate token id: %w", err)
	}
	return hex.EncodeToString(b), nil
}
