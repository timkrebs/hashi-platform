package httpapi

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"crypto"

	"github.com/timkrebs/auth-service/internal/auth"
	"github.com/timkrebs/auth-service/internal/observability"
)

type stubVault struct {
	key       *rsa.PrivateKey
	denyLogin bool
	vaultDown bool
}

func (s *stubVault) Sign(_ context.Context, _, _ string, data []byte) ([]byte, int, error) {
	sum := sha256.Sum256(data)
	sig, err := rsa.SignPKCS1v15(rand.Reader, s.key, crypto.SHA256, sum[:])
	return sig, 1, err
}

// vaultStatusErr carries an HTTP status the way the Vault client's APIError
// does: a 4xx is a rejection, anything else is an outage.
type vaultStatusErr struct{ code int }

func (e vaultStatusErr) Error() string   { return "vault status" }
func (e vaultStatusErr) StatusCode() int { return e.code }

func (s *stubVault) VerifyUserpass(_ context.Context, _, _, _ string) error {
	if s.vaultDown {
		return io.ErrUnexpectedEOF // a transport failure, not a rejection
	}
	if s.denyLogin {
		return vaultStatusErr{code: 400}
	}
	return nil
}

func (s *stubVault) PublicKeys(_ context.Context, _, _ string) (map[int]*rsa.PublicKey, int, error) {
	return map[int]*rsa.PublicKey{1: &s.key.PublicKey}, 1, nil
}

// An outage must surface as 503, never as 401 -- otherwise the status code
// itself misleads whoever is debugging.
func TestTokenEndpointReportsVaultOutageAsUnavailable(t *testing.T) {
	s := newTestServer(t, false)
	s.auth = nil // replaced below
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("key: %v", err)
	}
	sv := &stubVault{key: k, vaultDown: true}
	s.auth = auth.NewService(sv, sv, sv, auth.Options{
		TransitMount: "transit", SigningKey: "k", UserpassMount: "userpass",
		Issuer: "https://auth.test", Audience: "test", TokenTTL: time.Minute,
	})

	rec := httptest.NewRecorder()
	s.handleToken(rec, httptest.NewRequest(http.MethodPost, "/v1/token",
		strings.NewReader(`{"username":"dev1","password":"pw"}`)))

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503 when Vault is unreachable", rec.Code)
	}
}

func newTestServer(t *testing.T, deny bool) *Server {
	t.Helper()
	k, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("key: %v", err)
	}
	sv := &stubVault{key: k, denyLogin: deny}
	svc := auth.NewService(sv, sv, sv, auth.Options{
		TransitMount: "transit", SigningKey: "k", UserpassMount: "userpass",
		Issuer: "https://auth.test", Audience: "test", TokenTTL: time.Minute,
	})
	ready := &observability.Readiness{}
	ready.Set(true)
	return New(svc, slog.New(slog.DiscardHandler), ready, ":0", ":0")
}

func TestTokenEndpoint(t *testing.T) {
	s := newTestServer(t, false)

	req := httptest.NewRequest(http.MethodPost, "/v1/token",
		strings.NewReader(`{"username":"dev1","password":"pw"}`))
	rec := httptest.NewRecorder()
	s.handleToken(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body)
	}
	// Credentials must never be cached by an intermediary.
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q, want no-store", got)
	}

	var out struct {
		AccessToken string `json:"access_token"`
		TokenType   string `json:"token_type"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if out.TokenType != "Bearer" || out.ExpiresIn <= 0 {
		t.Errorf("response = %+v", out)
	}
	if strings.Count(out.AccessToken, ".") != 2 {
		t.Errorf("access_token is not a JWT: %q", out.AccessToken)
	}
}

func TestTokenEndpointRejectsBadCredentials(t *testing.T) {
	s := newTestServer(t, true)

	req := httptest.NewRequest(http.MethodPost, "/v1/token",
		strings.NewReader(`{"username":"dev1","password":"wrong"}`))
	rec := httptest.NewRecorder()
	s.handleToken(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
	// The message must not reveal whether the user exists.
	body := strings.ToLower(rec.Body.String())
	for _, leak := range []string{"unknown user", "no such user", "user not found"} {
		if strings.Contains(body, leak) {
			t.Errorf("response distinguishes unknown user from wrong password: %s", rec.Body)
		}
	}
}

func TestTokenEndpointRejectsMalformedBody(t *testing.T) {
	s := newTestServer(t, false)
	for _, body := range []string{`not json`, `{}`, `{"username":"dev1"}`, `{"username":"a","password":"b","extra":1}`} {
		rec := httptest.NewRecorder()
		s.handleToken(rec, httptest.NewRequest(http.MethodPost, "/v1/token", strings.NewReader(body)))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("body %q -> status %d, want 400", body, rec.Code)
		}
	}
}

// Liveness must not depend on Vault: if it did, a Vault restart would make
// Kubernetes kill every auth pod at once.
func TestHealthzIgnoresReadiness(t *testing.T) {
	s := newTestServer(t, false)
	s.ready.Set(false)

	rec := httptest.NewRecorder()
	s.handleHealthz(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("healthz = %d while unready, want 200", rec.Code)
	}

	rec = httptest.NewRecorder()
	s.handleReadyz(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("readyz = %d while unready, want 503", rec.Code)
	}
}

func TestJWKSEndpoint(t *testing.T) {
	s := newTestServer(t, false)
	rec := httptest.NewRecorder()
	s.handleJWKS(rec, httptest.NewRequest(http.MethodGet, "/.well-known/jwks.json", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var out struct {
		Keys []map[string]any `json:"keys"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(out.Keys) == 0 {
		t.Fatal("jwks is empty")
	}
	if _, ok := out.Keys[0]["d"]; ok {
		t.Error("jwks exposes the private exponent")
	}
}
