package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// fakeVault stands in for Transit and userpass. It signs with a real RSA key,
// so the tests verify an actual RS256 signature rather than a stub.
type fakeVault struct {
	key       *rsa.PrivateKey
	version   atomic.Int64
	signCalls atomic.Int64
	denyLogin bool
	loginErr  error
	signErr   error
}

// statusErr mimics the Vault client's APIError: it carries the HTTP status, and
// that status is how a rejection is told apart from an outage.
type statusErr struct{ code int }

func (e statusErr) Error() string   { return "vault status" }
func (e statusErr) StatusCode() int { return e.code }

func newFakeVault(t *testing.T) *fakeVault {
	t.Helper()
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	f := &fakeVault{key: k}
	f.version.Store(1)
	return f
}

func (f *fakeVault) Sign(_ context.Context, _, _ string, data []byte) ([]byte, int, error) {
	f.signCalls.Add(1)
	if f.signErr != nil {
		return nil, 0, f.signErr
	}
	sum := sha256.Sum256(data)
	sig, err := rsa.SignPKCS1v15(rand.Reader, f.key, cryptoSHA256, sum[:])
	if err != nil {
		return nil, 0, err
	}
	return sig, int(f.version.Load()), nil
}

func (f *fakeVault) VerifyUserpass(_ context.Context, _, _, _ string) error {
	if f.loginErr != nil {
		return f.loginErr
	}
	if f.denyLogin {
		// Vault answers a wrong password with 400, not with a transport error.
		return statusErr{code: 400}
	}
	return nil
}

func (f *fakeVault) PublicKeys(_ context.Context, _, _ string) (map[int]*rsa.PublicKey, int, error) {
	v := int(f.version.Load())
	return map[int]*rsa.PublicKey{v: &f.key.PublicKey}, v, nil
}

func newService(f *fakeVault) *Service {
	return NewService(f, f, f, Options{
		TransitMount:  "transit",
		SigningKey:    "auth-service-jwt",
		UserpassMount: "userpass",
		Issuer:        "https://auth.test",
		Audience:      "hashi-platform",
		TokenTTL:      15 * time.Minute,
	})
}

func TestIssueProducesVerifiableToken(t *testing.T) {
	f := newFakeVault(t)
	svc := newService(f)
	ctx := context.Background()

	if err := svc.Warm(ctx); err != nil {
		t.Fatalf("warm: %v", err)
	}

	token, expiresAt, err := svc.Issue(ctx, "dev1", "pw", []string{"read"})
	if err != nil {
		t.Fatalf("issue: %v", err)
	}

	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("token has %d segments, want 3", len(parts))
	}

	// The signature must cover exactly header.payload -- this is what every
	// verifier reconstructs, and getting it wrong is the classic JWT bug.
	signingInput := parts[0] + "." + parts[1]
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatalf("signature is not base64url: %v", err)
	}
	sum := sha256.Sum256([]byte(signingInput))
	if err := rsa.VerifyPKCS1v15(&f.key.PublicKey, cryptoSHA256, sum[:], sig); err != nil {
		t.Fatalf("signature does not verify: %v", err)
	}

	var hdr struct {
		Alg string `json:"alg"`
		Typ string `json:"typ"`
		Kid string `json:"kid"`
	}
	decodeSegment(t, parts[0], &hdr)
	if hdr.Alg != "RS256" || hdr.Typ != "JWT" {
		t.Errorf("header = %+v, want RS256/JWT", hdr)
	}
	if hdr.Kid != "1" {
		t.Errorf("kid = %q, want the signing key version %q", hdr.Kid, "1")
	}

	var claims Claims
	decodeSegment(t, parts[1], &claims)
	if claims.Subject != "dev1" {
		t.Errorf("sub = %q, want dev1", claims.Subject)
	}
	if claims.Issuer != "https://auth.test" || claims.Audience != "hashi-platform" {
		t.Errorf("iss/aud = %q/%q", claims.Issuer, claims.Audience)
	}
	if claims.JWTID == "" {
		t.Error("jti is empty; tokens must be individually identifiable")
	}
	if claims.ExpiresAt <= claims.IssuedAt {
		t.Error("exp must be after iat")
	}
	if got := time.Unix(claims.ExpiresAt, 0); !got.Equal(expiresAt) {
		t.Errorf("returned expiry %s does not match exp claim %s", expiresAt, got)
	}
}

// One login must cost exactly one signing call. An extra round trip to learn
// the key version would double Vault traffic on the critical path.
func TestIssueSignsOnce(t *testing.T) {
	f := newFakeVault(t)
	svc := newService(f)
	ctx := context.Background()
	if err := svc.Warm(ctx); err != nil {
		t.Fatalf("warm: %v", err)
	}

	before := f.signCalls.Load()
	if _, _, err := svc.Issue(ctx, "dev1", "pw", nil); err != nil {
		t.Fatalf("issue: %v", err)
	}
	if got := f.signCalls.Load() - before; got != 1 {
		t.Errorf("Sign called %d times per login, want 1", got)
	}
}

func TestIssueRejectsBadCredentials(t *testing.T) {
	f := newFakeVault(t)
	f.denyLogin = true
	svc := newService(f)

	_, _, err := svc.Issue(context.Background(), "dev1", "wrong", nil)
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("err = %v, want ErrInvalidCredentials", err)
	}
	if f.signCalls.Load() != 0 {
		t.Error("signed a token for invalid credentials")
	}
}

// A Vault outage must surface as an error, never as an unsigned token.
func TestIssueFailsWhenVaultCannotSign(t *testing.T) {
	f := newFakeVault(t)
	svc := newService(f)
	if err := svc.Warm(context.Background()); err != nil {
		t.Fatalf("warm: %v", err)
	}
	f.signErr = errors.New("vault returned 503")

	token, _, err := svc.Issue(context.Background(), "dev1", "pw", nil)
	if err == nil {
		t.Fatal("expected an error when Vault cannot sign")
	}
	if token != "" {
		t.Errorf("returned a token despite the signing failure: %q", token)
	}
}

// A Vault outage must NOT be reported as bad credentials. Getting this wrong
// tells every user their password is wrong during an outage, and sends whoever
// is on call looking for a credentials problem.
func TestVaultOutageIsNotReportedAsBadCredentials(t *testing.T) {
	for _, tc := range []struct {
		name string
		err  error
	}{
		{name: "connection refused", err: errors.New("dial tcp 10.0.0.1:8200: connect: connection refused")},
		{name: "vault 500", err: statusErr{code: 500}},
		{name: "vault 503", err: statusErr{code: 503}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newFakeVault(t)
			f.loginErr = tc.err
			svc := newService(f)

			_, _, err := svc.Issue(context.Background(), "dev1", "pw", nil)
			if err == nil {
				t.Fatal("expected an error")
			}
			if errors.Is(err, ErrInvalidCredentials) {
				t.Errorf("reported a Vault outage as invalid credentials: %v", err)
			}
		})
	}
}

// A 4xx from Vault really is a rejection and must stay one.
func TestVault4xxIsReportedAsBadCredentials(t *testing.T) {
	for _, code := range []int{400, 401, 403} {
		f := newFakeVault(t)
		f.loginErr = statusErr{code: code}
		svc := newService(f)

		_, _, err := svc.Issue(context.Background(), "dev1", "pw", nil)
		if !errors.Is(err, ErrInvalidCredentials) {
			t.Errorf("status %d gave %v, want ErrInvalidCredentials", code, err)
		}
	}
}

func TestJWKSExposesOnlyPublicMaterial(t *testing.T) {
	f := newFakeVault(t)
	svc := newService(f)

	keys, err := svc.JWKS(context.Background())
	if err != nil {
		t.Fatalf("jwks: %v", err)
	}
	if len(keys) != 1 {
		t.Fatalf("got %d keys, want 1", len(keys))
	}
	k := keys[0]
	if k.Kty != "RSA" || k.Alg != "RS256" || k.Use != "sig" {
		t.Errorf("jwk = %+v", k)
	}
	if k.N == "" || k.E == "" {
		t.Error("modulus or exponent missing")
	}
	// 65537 is the standard exponent and must encode to AQAB.
	if k.E != "AQAB" {
		t.Errorf("e = %q, want AQAB", k.E)
	}

	raw, err := json.Marshal(k)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	// A private field leaking into JWKS would publish the signing key.
	for _, forbidden := range []string{`"d"`, `"p"`, `"q"`, `"dp"`, `"dq"`, `"qi"`} {
		if strings.Contains(string(raw), forbidden) {
			t.Errorf("JWKS contains private key field %s: %s", forbidden, raw)
		}
	}
}

func decodeSegment(t *testing.T, seg string, out any) {
	t.Helper()
	b, err := base64.RawURLEncoding.DecodeString(seg)
	if err != nil {
		t.Fatalf("segment is not base64url: %v", err)
	}
	if err := json.Unmarshal(b, out); err != nil {
		t.Fatalf("segment is not JSON: %v", err)
	}
}
