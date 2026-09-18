package httpapi

import (
	"crypto/rand"
	"crypto/rsa"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/timkrebs/auth-service/internal/auth"
	"github.com/timkrebs/auth-service/internal/observability"
	"github.com/timkrebs/auth-service/internal/secrets"
)

type stubKeys struct {
	key *rsa.PrivateKey
	err error
}

func (s *stubKeys) Signing() (*rsa.PrivateKey, string, error) {
	if s.err != nil {
		return nil, "", s.err
	}
	return s.key, "kid-1", nil
}

type stubVerifier struct{ err error }

func (s *stubVerifier) Verify(_, _ string) error { return s.err }

func newTestServer(t *testing.T, keys *stubKeys, v *stubVerifier) *Server {
	t.Helper()
	if keys.key == nil && keys.err == nil {
		k, err := rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			t.Fatalf("key: %v", err)
		}
		keys.key = k
	}
	svc := auth.NewService(keys, v, auth.Options{
		Issuer: "https://auth.test", Audience: "test", TokenTTL: time.Minute,
	})
	ready := &observability.Readiness{}
	ready.Set(true)
	return New(svc, slog.New(slog.DiscardHandler), ready, ":0", ":0")
}

func post(t *testing.T, s *Server, body string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	s.handleToken(rec, httptest.NewRequest(http.MethodPost, "/v1/token", strings.NewReader(body)))
	return rec
}

func TestTokenEndpoint(t *testing.T) {
	s := newTestServer(t, &stubKeys{}, &stubVerifier{})
	rec := post(t, s, `{"username":"dev1","password":"pw"}`)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body)
	}
	// Credentials must not be cached by any intermediary.
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
	s := newTestServer(t, &stubKeys{}, &stubVerifier{err: secrets.ErrInvalidCredentials})
	rec := post(t, s, `{"username":"dev1","password":"wrong"}`)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
	body := strings.ToLower(rec.Body.String())
	for _, leak := range []string{"unknown user", "no such user", "user not found"} {
		if strings.Contains(body, leak) {
			t.Errorf("response distinguishes unknown user from wrong password: %s", rec.Body)
		}
	}
}

// Before the operator has synced the Secret the answer must be 503, not 401.
// A 401 would send every user and every operator after a credentials problem
// that does not exist.
func TestTokenEndpointReportsUnsyncedSecretAsUnavailable(t *testing.T) {
	s := newTestServer(t,
		&stubKeys{err: secrets.ErrNotLoaded},
		&stubVerifier{err: secrets.ErrNotLoaded})

	rec := post(t, s, `{"username":"dev1","password":"pw"}`)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503 before the secret is synced", rec.Code)
	}
}

func TestTokenEndpointRejectsMalformedBody(t *testing.T) {
	s := newTestServer(t, &stubKeys{}, &stubVerifier{})
	for _, body := range []string{`not json`, `{}`, `{"username":"dev1"}`, `{"username":"a","password":"b","extra":1}`} {
		if rec := post(t, s, body); rec.Code != http.StatusBadRequest {
			t.Errorf("body %q -> status %d, want 400", body, rec.Code)
		}
	}
}

// Liveness must not depend on the secret: if it did, a sync problem would make
// Kubernetes restart every pod instead of just taking them out of rotation.
func TestHealthzIgnoresReadiness(t *testing.T) {
	s := newTestServer(t, &stubKeys{}, &stubVerifier{})
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
	s := newTestServer(t, &stubKeys{}, &stubVerifier{})
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
