// Package vault is a minimal client for the three Vault endpoints this service
// needs. It deliberately does not pull in hashicorp/vault/api: three endpoints
// over net/http make the exchange visible, which matters more in an example
// than the convenience of the full SDK.
package vault

import (
	"bytes"
	"context"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/timkrebs/auth-service/internal/observability"
)

// Client talks to Vault as the workload identity the Agent sidecar obtained.
type Client struct {
	addr      string
	namespace string
	tokenPath string
	httpc     *http.Client
	log       *slog.Logger

	mu    sync.RWMutex
	token string
}

func New(addr, namespace, tokenPath string, log *slog.Logger) *Client {
	return &Client{
		addr:      strings.TrimSuffix(addr, "/"),
		namespace: namespace,
		tokenPath: tokenPath,
		log:       log,
		httpc: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// ReloadToken re-reads the file the Vault Agent writes.
//
// The agent renews the token and rewrites this file; a service that reads it
// only once keeps presenting an expired token and every sign call starts
// failing with 403 while the pod still looks healthy.
func (c *Client) ReloadToken() error {
	b, err := os.ReadFile(c.tokenPath)
	if err != nil {
		return fmt.Errorf("read vault token: %w", err)
	}
	tok := strings.TrimSpace(string(b))
	if tok == "" {
		return fmt.Errorf("vault token file %s is empty", c.tokenPath)
	}

	c.mu.Lock()
	changed := c.token != tok
	c.token = tok
	c.mu.Unlock()

	if changed {
		c.log.Info("vault token reloaded", "path", c.tokenPath)
	}
	return nil
}

// WatchToken re-reads the token file until ctx is cancelled.
func (c *Client) WatchToken(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if err := c.ReloadToken(); err != nil {
				c.log.Warn("vault token reload failed", "error", err)
			}
		}
	}
}

func (c *Client) currentToken() string {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.token
}

// do performs one request, records metrics, and decodes the JSON body.
func (c *Client) do(ctx context.Context, op, method, path string, body any, authenticated bool, out any) error {
	start := time.Now()
	err := c.doInner(ctx, method, path, body, authenticated, out)
	observability.VaultDuration.WithLabelValues(op).Observe(time.Since(start).Seconds())
	if err != nil {
		observability.VaultRequests.WithLabelValues(op, "error").Inc()
		return err
	}
	observability.VaultRequests.WithLabelValues(op, "ok").Inc()
	return nil
}

func (c *Client) doInner(ctx context.Context, method, path string, body any, authenticated bool, out any) error {
	var rdr io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("encode request: %w", err)
		}
		rdr = bytes.NewReader(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.addr+"/v1/"+strings.TrimPrefix(path, "/"), rdr)
	if err != nil {
		return err
	}
	// Vault Enterprise namespaces are a header, not a path prefix. Omitting it
	// silently targets the root namespace, where none of these mounts exist.
	if c.namespace != "" {
		req.Header.Set("X-Vault-Namespace", c.namespace)
	}
	if authenticated {
		tok := c.currentToken()
		if tok == "" {
			return fmt.Errorf("no vault token available yet")
		}
		req.Header.Set("X-Vault-Token", tok)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpc.Do(req)
	if err != nil {
		return fmt.Errorf("vault request: %w", err)
	}
	defer resp.Body.Close()

	// Cap the body: a compromised or misconfigured endpoint should not be able
	// to exhaust memory here.
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("read vault response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return &APIError{Status: resp.StatusCode, Body: strings.TrimSpace(string(raw))}
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(raw, out)
}

// APIError carries Vault's status code so callers can tell "wrong password"
// (400/403 from userpass) from "Vault is broken" (5xx).
type APIError struct {
	Status int
	Body   string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("vault returned %d: %s", e.Status, e.Body)
}

// StatusCode lets callers classify the failure without importing this package.
// A 4xx from the login endpoint means the credentials were rejected; anything
// else means Vault could not answer, and the two must not look the same to the
// user.
func (e *APIError) StatusCode() int { return e.Status }

// VerifyUserpass checks a username and password against Vault's userpass auth.
//
// Credential verification is delegated to Vault on purpose: this service never
// stores or hashes a password, so there is no user database to leak. The login
// endpoint is unauthenticated, so it needs no policy.
//
// The Vault token this returns is discarded -- only the fact that login
// succeeded matters here.
func (c *Client) VerifyUserpass(ctx context.Context, mount, username, password string) error {
	path := fmt.Sprintf("auth/%s/login/%s", mount, username)
	return c.do(ctx, "userpass_login", http.MethodPost, path,
		map[string]string{"password": password}, false, nil)
}

type signResponse struct {
	Data struct {
		Signature string `json:"signature"`
	} `json:"data"`
}

// Sign signs data with the Transit key and returns the raw signature bytes.
//
// Two details that are easy to get wrong and fail confusingly:
//
//   - Transit's default signature_algorithm for RSA keys is PSS. RS256 in a JWT
//     means PKCS#1 v1.5, so it has to be set explicitly, otherwise every
//     verifier rejects the token with no useful message.
//   - The response is "vault:v<n>:<standard base64>", not a bare signature. The
//     prefix carries the key version and has to be stripped before the bytes
//     can be re-encoded as base64url for the JWT.
func (c *Client) Sign(ctx context.Context, mount, key string, data []byte) ([]byte, int, error) {
	var out signResponse
	err := c.do(ctx, "transit_sign", http.MethodPost,
		fmt.Sprintf("%s/sign/%s", mount, key),
		map[string]string{
			"input":               base64.StdEncoding.EncodeToString(data),
			"hash_algorithm":      "sha2-256",
			"signature_algorithm": "pkcs1v15",
		}, true, &out)
	if err != nil {
		return nil, 0, err
	}

	version, encoded, err := splitSignature(out.Data.Signature)
	if err != nil {
		return nil, 0, err
	}
	sig, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, 0, fmt.Errorf("decode signature: %w", err)
	}
	return sig, version, nil
}

func splitSignature(s string) (int, string, error) {
	parts := strings.SplitN(s, ":", 3)
	if len(parts) != 3 || parts[0] != "vault" {
		return 0, "", fmt.Errorf("unexpected signature format %q", s)
	}
	version, err := strconv.Atoi(strings.TrimPrefix(parts[1], "v"))
	if err != nil {
		return 0, "", fmt.Errorf("unexpected key version in %q", s)
	}
	return version, parts[2], nil
}

type keyResponse struct {
	Data struct {
		LatestVersion int `json:"latest_version"`
		Keys          map[string]struct {
			PublicKey string `json:"public_key"`
		} `json:"keys"`
	} `json:"data"`
}

// PublicKeys returns every published public key version, so JWKS can serve the
// previous one too. Without that, rotating the key invalidates every token
// still in flight.
func (c *Client) PublicKeys(ctx context.Context, mount, key string) (map[int]*rsa.PublicKey, int, error) {
	var out keyResponse
	if err := c.do(ctx, "transit_read_key", http.MethodGet,
		fmt.Sprintf("%s/keys/%s", mount, key), nil, true, &out); err != nil {
		return nil, 0, err
	}

	keys := make(map[int]*rsa.PublicKey, len(out.Data.Keys))
	for v, k := range out.Data.Keys {
		version, err := strconv.Atoi(v)
		if err != nil || k.PublicKey == "" {
			continue
		}
		pub, err := parseRSAPublicKey(k.PublicKey)
		if err != nil {
			return nil, 0, fmt.Errorf("key version %s: %w", v, err)
		}
		keys[version] = pub
	}
	if len(keys) == 0 {
		return nil, 0, fmt.Errorf("transit key %s exposes no public key; is it an RSA key?", key)
	}
	return keys, out.Data.LatestVersion, nil
}

func parseRSAPublicKey(pemStr string) (*rsa.PublicKey, error) {
	block, _ := pem.Decode([]byte(pemStr))
	if block == nil {
		return nil, fmt.Errorf("public key is not PEM")
	}
	parsed, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse public key: %w", err)
	}
	pub, ok := parsed.(*rsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("public key is %T, want RSA", parsed)
	}
	return pub, nil
}
