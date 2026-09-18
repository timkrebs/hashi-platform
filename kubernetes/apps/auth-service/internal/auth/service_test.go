package auth

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/timkrebs/auth-service/internal/secrets"
)

type fakeKeys struct {
	key *rsa.PrivateKey
	err error
}

func (f *fakeKeys) Signing() (*rsa.PrivateKey, string, error) {
	if f.err != nil {
		return nil, "", f.err
	}
	return f.key, "test-kid", nil
}

type fakeVerifier struct{ err error }

func (f *fakeVerifier) Verify(_, _ string) error { return f.err }

func newService(t *testing.T, keys *fakeKeys, v *fakeVerifier) *Service {
	t.Helper()
	return NewService(keys, v, Options{
		Issuer: "https://auth.test", Audience: "hashi-platform", TokenTTL: 15 * time.Minute,
	})
}

func newKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	return k
}

func TestIssueProducesVerifiableToken(t *testing.T) {
	key := newKey(t)
	svc := newService(t, &fakeKeys{key: key}, &fakeVerifier{})

	token, expiresAt, err := svc.Issue("dev1", "pw", []string{"read"})
	if err != nil {
		t.Fatalf("issue: %v", err)
	}

	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("token has %d segments, want 3", len(parts))
	}

	// The signature must cover exactly header.payload -- what every verifier
	// reconstructs. Signing anything else passes your own tests and fails
	// everywhere else.
	signingInput := parts[0] + "." + parts[1]
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatalf("signature is not base64url: %v", err)
	}
	sum := sha256.Sum256([]byte(signingInput))
	if err := rsa.VerifyPKCS1v15(&key.PublicKey, crypto.SHA256, sum[:], sig); err != nil {
		t.Fatalf("signature does not verify: %v", err)
	}

	var hdr struct{ Alg, Typ, Kid string }
	decode(t, parts[0], &hdr)
	if hdr.Alg != "RS256" || hdr.Typ != "JWT" || hdr.Kid != "test-kid" {
		t.Errorf("header = %+v", hdr)
	}

	var claims Claims
	decode(t, parts[1], &claims)
	if claims.Subject != "dev1" || claims.Issuer != "https://auth.test" || claims.Audience != "hashi-platform" {
		t.Errorf("claims = %+v", claims)
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

// PS256 would also verify as "an RSA signature", so assert the scheme rather
// than just that verification passes.
func TestSignatureIsPKCS1v15NotPSS(t *testing.T) {
	key := newKey(t)
	svc := newService(t, &fakeKeys{key: key}, &fakeVerifier{})

	token, _, err := svc.Issue("dev1", "pw", nil)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	parts := strings.Split(token, ".")
	sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
	sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))

	if err := rsa.VerifyPSS(&key.PublicKey, crypto.SHA256, sum[:], sig, nil); err == nil {
		t.Error("signature verifies as PSS; RS256 must be PKCS#1 v1.5")
	}
}

func TestIssueRejectsBadCredentials(t *testing.T) {
	svc := newService(t, &fakeKeys{key: newKey(t)}, &fakeVerifier{err: secrets.ErrInvalidCredentials})

	if _, _, err := svc.Issue("dev1", "wrong", nil); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("err = %v, want ErrInvalidCredentials", err)
	}
}

// A secret that has not synced yet must NOT look like a wrong password --
// otherwise every user is told their credentials are bad while the real
// problem is that the operator has not written the Secret.
func TestUnsyncedSecretIsNotReportedAsBadCredentials(t *testing.T) {
	svc := newService(t, &fakeKeys{err: secrets.ErrNotLoaded}, &fakeVerifier{err: secrets.ErrNotLoaded})

	_, _, err := svc.Issue("dev1", "pw", nil)
	if err == nil {
		t.Fatal("expected an error")
	}
	if errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("reported an unsynced secret as invalid credentials: %v", err)
	}
}

func TestJWKSExposesOnlyPublicMaterial(t *testing.T) {
	svc := newService(t, &fakeKeys{key: newKey(t)}, &fakeVerifier{})

	keys, err := svc.JWKS()
	if err != nil {
		t.Fatalf("jwks: %v", err)
	}
	if len(keys) != 1 {
		t.Fatalf("got %d keys, want 1", len(keys))
	}
	k := keys[0]
	if k.Kty != "RSA" || k.Alg != "RS256" || k.Use != "sig" || k.Kid != "test-kid" {
		t.Errorf("jwk = %+v", k)
	}
	// 65537 is the standard exponent; JWK wants the minimal big-endian form.
	if k.E != "AQAB" {
		t.Errorf("e = %q, want AQAB", k.E)
	}

	raw, err := json.Marshal(k)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	for _, forbidden := range []string{`"d"`, `"p"`, `"q"`, `"dp"`, `"dq"`, `"qi"`} {
		if strings.Contains(string(raw), forbidden) {
			t.Errorf("JWKS contains private key field %s: %s", forbidden, raw)
		}
	}
}

func TestJWKSFailsBeforeSync(t *testing.T) {
	svc := newService(t, &fakeKeys{err: secrets.ErrNotLoaded}, &fakeVerifier{})
	if _, err := svc.JWKS(); err == nil {
		t.Fatal("JWKS returned keys before the secret was synced")
	}
}

func decode(t *testing.T, seg string, out any) {
	t.Helper()
	b, err := base64.RawURLEncoding.DecodeString(seg)
	if err != nil {
		t.Fatalf("segment is not base64url: %v", err)
	}
	if err := json.Unmarshal(b, out); err != nil {
		t.Fatalf("segment is not JSON: %v", err)
	}
}
