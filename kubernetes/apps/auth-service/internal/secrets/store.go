// Package secrets reads what the Vault Secrets Operator syncs into a plain
// Kubernetes Secret, mounted here as a directory of files.
//
// The service makes no request to Vault. The operator authenticates with this
// namespace's ServiceAccount, reads the one KV path its Vault policy allows,
// and writes the result into a Secret; the kubelet projects that Secret as
// files. Vault is therefore not on the request path at all -- if Vault is down,
// tokens keep being issued from the key already on disk.
//
// The trade-off, stated plainly: the signing key now exists outside Vault, in
// etcd and in this pod's memory. EKS envelope-encrypts Secrets with KMS, and
// the operator re-syncs on rotation, but a compromised pod can mint tokens for
// as long as it holds the key. Signing through Vault's Transit engine avoided
// that and cost a Vault round trip per login.
package secrets

import (
	"crypto/rsa"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/crypto/bcrypt"
)

// File names inside the mounted directory. They are the keys of the Vault KV
// secret, which the operator copies verbatim into the Kubernetes Secret.
const (
	signingKeyFile = "signing-key"
	usersFile      = "users"
)

// Store holds what was on disk when the pod started.
//
// It is read once and never reloaded: when the operator updates the Secret it
// also restarts this Deployment (rolloutRestartTargets), so a new key arrives
// as a new pod. That is deliberate -- a key swapped underneath a running
// process would sign some tokens with the old key and some with the new one,
// and both would be in flight with the same kid if the reload were partial.
type Store struct {
	key   *rsa.PrivateKey
	keyID string
	users map[string]string // username -> bcrypt hash
}

// Load reads the directory the Secret is mounted at.
func Load(dir string) (*Store, error) {
	keyPEM, err := os.ReadFile(filepath.Join(dir, signingKeyFile))
	if err != nil {
		return nil, fmt.Errorf("read signing key: %w (is the VaultStaticSecret synced?)", err)
	}
	key, err := parsePrivateKey(keyPEM)
	if err != nil {
		return nil, err
	}

	usersJSON, err := os.ReadFile(filepath.Join(dir, usersFile))
	if err != nil {
		return nil, fmt.Errorf("read users: %w", err)
	}
	users := map[string]string{}
	if err := json.Unmarshal(usersJSON, &users); err != nil {
		return nil, fmt.Errorf("users must be a JSON object of username to bcrypt hash: %w", err)
	}
	if len(users) == 0 {
		return nil, fmt.Errorf("users is empty; the service would reject every login")
	}
	for name, hash := range users {
		// Fail at startup rather than on the first login attempt: a plaintext
		// password in this field would otherwise be found by a user, not by us.
		if _, err := bcrypt.Cost([]byte(hash)); err != nil {
			return nil, fmt.Errorf("user %q does not hold a bcrypt hash: %w", name, err)
		}
	}

	return &Store{key: key, keyID: thumbprint(&key.PublicKey), users: users}, nil
}

func (s *Store) PrivateKey() *rsa.PrivateKey { return s.key }

// KeyID is the RFC 7638 JWK thumbprint of the public key.
//
// Derived rather than configured: it changes exactly when the key changes, so
// a rotation cannot accidentally reuse a kid and leave verifiers matching a
// token against the wrong key.
func (s *Store) KeyID() string { return s.keyID }

// dummyHash makes an unknown username cost the same as a known one. Without it
// the response time alone tells an attacker which usernames exist.
var dummyHash = []byte("$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy")

// Verify checks a password. It reports nothing about which half was wrong.
func (s *Store) Verify(username, password string) error {
	hash, ok := s.users[username]
	if !ok {
		_ = bcrypt.CompareHashAndPassword(dummyHash, []byte(password))
		return ErrInvalidCredentials
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)); err != nil {
		return ErrInvalidCredentials
	}
	return nil
}

// ErrInvalidCredentials is returned for both an unknown user and a wrong
// password.
var ErrInvalidCredentials = fmt.Errorf("invalid credentials")

func parsePrivateKey(raw []byte) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, fmt.Errorf("signing key is not PEM")
	}
	if x509.IsEncryptedPEMBlock(block) { //nolint:staticcheck // the check is the point
		return nil, fmt.Errorf("signing key is passphrase-encrypted; this service has no passphrase")
	}

	// Accept both PKCS#1 ("RSA PRIVATE KEY") and PKCS#8 ("PRIVATE KEY").
	// openssl writes one or the other depending on the flags used, and getting
	// the wrong one is otherwise a puzzling parse failure.
	if key, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return checkSize(key)
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("signing key is neither PKCS#1 nor PKCS#8: %w", err)
	}
	key, ok := parsed.(*rsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("signing key is %T, want RSA (the tokens are RS256)", parsed)
	}
	return checkSize(key)
}

func checkSize(key *rsa.PrivateKey) (*rsa.PrivateKey, error) {
	if bits := key.N.BitLen(); bits < 2048 {
		return nil, fmt.Errorf("signing key is %d bits; RS256 needs at least 2048", bits)
	}
	return key, nil
}

// thumbprint implements RFC 7638 for RSA: SHA-256 over the canonical JSON of
// the required members, in lexicographic order, with no whitespace.
func thumbprint(pub *rsa.PublicKey) string {
	canonical := fmt.Sprintf(`{"e":"%s","kty":"RSA","n":"%s"}`,
		Base64URL(bigEndian(pub.E)), Base64URL(pub.N.Bytes()))
	sum := sha256.Sum256([]byte(canonical))
	return Base64URL(sum[:])
}

// Base64URL is the unpadded base64url encoding JWK uses throughout.
func Base64URL(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

// BigEndian exposes the exponent encoding so the JWKS handler agrees with the
// thumbprint. Trailing zero bytes are trimmed, as JWK requires the minimal
// representation.
func bigEndian(e int) []byte {
	b := []byte{byte(e >> 24), byte(e >> 16), byte(e >> 8), byte(e)}
	for len(b) > 1 && b[0] == 0 {
		b = b[1:]
	}
	return b
}

// ExponentBytes is bigEndian, exported for the JWKS handler.
func ExponentBytes(e int) []byte { return bigEndian(e) }

// ConstantTimeEqual is used where a comparison must not leak length or content.
func ConstantTimeEqual(a, b string) bool {
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}
