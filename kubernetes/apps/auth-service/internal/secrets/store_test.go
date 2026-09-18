package secrets

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"golang.org/x/crypto/bcrypt"
)

func writeStore(t *testing.T, keyBits int, users map[string]string, pkcs8 bool) string {
	t.Helper()
	dir := t.TempDir()

	key, err := rsa.GenerateKey(rand.Reader, keyBits)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	var block *pem.Block
	if pkcs8 {
		der, err := x509.MarshalPKCS8PrivateKey(key)
		if err != nil {
			t.Fatalf("marshal pkcs8: %v", err)
		}
		block = &pem.Block{Type: "PRIVATE KEY", Bytes: der}
	} else {
		block = &pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)}
	}
	if err := os.WriteFile(filepath.Join(dir, signingKeyFile), pem.EncodeToMemory(block), 0o600); err != nil {
		t.Fatalf("write key: %v", err)
	}

	raw, err := json.Marshal(users)
	if err != nil {
		t.Fatalf("marshal users: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, usersFile), raw, 0o600); err != nil {
		t.Fatalf("write users: %v", err)
	}
	return dir
}

func hash(t *testing.T, pw string) string {
	t.Helper()
	h, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("bcrypt: %v", err)
	}
	return string(h)
}

// Both PEM encodings must work: openssl writes PKCS#1 or PKCS#8 depending on
// the flags, and whoever writes the Vault secret should not have to know which.
func TestLoadAcceptsBothPEMEncodings(t *testing.T) {
	for _, pkcs8 := range []bool{false, true} {
		dir := writeStore(t, 2048, map[string]string{"dev1": hash(t, "pw")}, pkcs8)
		s, err := Load(dir)
		if err != nil {
			t.Fatalf("pkcs8=%v: %v", pkcs8, err)
		}
		if s.KeyID() == "" {
			t.Error("key id is empty")
		}
	}
}

// The kid is derived from the key, so it must be stable across loads and
// change when the key changes. A reused kid after a rotation makes verifiers
// match a token against the wrong key.
func TestKeyIDIsDerivedFromTheKey(t *testing.T) {
	dir := writeStore(t, 2048, map[string]string{"dev1": hash(t, "pw")}, false)
	a, err := Load(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	b, err := Load(dir)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if a.KeyID() != b.KeyID() {
		t.Errorf("kid changed between loads: %q vs %q", a.KeyID(), b.KeyID())
	}

	other := writeStore(t, 2048, map[string]string{"dev1": hash(t, "pw")}, false)
	c, err := Load(other)
	if err != nil {
		t.Fatalf("load other: %v", err)
	}
	if a.KeyID() == c.KeyID() {
		t.Error("two different keys produced the same kid")
	}
}

func TestVerify(t *testing.T) {
	dir := writeStore(t, 2048, map[string]string{"dev1": hash(t, "correct")}, false)
	s, err := Load(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	if err := s.Verify("dev1", "correct"); err != nil {
		t.Errorf("correct password rejected: %v", err)
	}
	if err := s.Verify("dev1", "wrong"); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("wrong password gave %v", err)
	}
	// An unknown user must be indistinguishable from a wrong password.
	if err := s.Verify("nobody", "anything"); !errors.Is(err, ErrInvalidCredentials) {
		t.Errorf("unknown user gave %v", err)
	}
}

func TestLoadRejectsBadInput(t *testing.T) {
	t.Run("key too small", func(t *testing.T) {
		dir := writeStore(t, 1024, map[string]string{"dev1": hash(t, "pw")}, false)
		if _, err := Load(dir); err == nil {
			t.Fatal("accepted a 1024-bit key for RS256")
		}
	})

	// The most dangerous mistake: a plaintext password in the users file would
	// otherwise be discovered by a user failing to log in, not by us.
	t.Run("plaintext password", func(t *testing.T) {
		dir := writeStore(t, 2048, map[string]string{"dev1": "hunter2"}, false)
		_, err := Load(dir)
		if err == nil {
			t.Fatal("accepted a plaintext password where a bcrypt hash belongs")
		}
	})

	t.Run("empty users", func(t *testing.T) {
		dir := writeStore(t, 2048, map[string]string{}, false)
		if _, err := Load(dir); err == nil {
			t.Fatal("accepted an empty user list")
		}
	})

	t.Run("key not PEM", func(t *testing.T) {
		dir := writeStore(t, 2048, map[string]string{"dev1": hash(t, "pw")}, false)
		if err := os.WriteFile(filepath.Join(dir, signingKeyFile), []byte("nope"), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := Load(dir); err == nil {
			t.Fatal("accepted a non-PEM signing key")
		}
	})

	// Both encrypted PEM forms must be reported as such, not as a parse error.
	// openssl produces the PKCS#8 form by default, which the deprecated
	// x509.IsEncryptedPEMBlock would not have caught at all.
	t.Run("passphrase-encrypted key", func(t *testing.T) {
		for _, block := range []*pem.Block{
			{Type: "RSA PRIVATE KEY", Headers: map[string]string{
				"Proc-Type": "4,ENCRYPTED", "DEK-Info": "AES-256-CBC,0123",
			}, Bytes: []byte("ciphertext")},
			{Type: "ENCRYPTED PRIVATE KEY", Bytes: []byte("ciphertext")},
		} {
			dir := writeStore(t, 2048, map[string]string{"dev1": hash(t, "pw")}, false)
			if err := os.WriteFile(filepath.Join(dir, signingKeyFile), pem.EncodeToMemory(block), 0o600); err != nil {
				t.Fatal(err)
			}
			_, err := Load(dir)
			if err == nil {
				t.Fatalf("%s: accepted a passphrase-encrypted key", block.Type)
			}
			if !strings.Contains(err.Error(), "passphrase") {
				t.Errorf("%s: error should name the cause, got %v", block.Type, err)
			}
		}
	})

	t.Run("missing directory", func(t *testing.T) {
		if _, err := Load(filepath.Join(t.TempDir(), "absent")); err == nil {
			t.Fatal("accepted a missing directory")
		}
	})
}

// Before the operator has synced anything, the holder must say so rather than
// hand out a nil key.
func TestHolderReportsNotLoaded(t *testing.T) {
	var h Holder
	if h.Loaded() {
		t.Error("an empty holder reports loaded")
	}
	if _, _, err := h.Signing(); !errors.Is(err, ErrNotLoaded) {
		t.Errorf("Signing gave %v, want ErrNotLoaded", err)
	}
	if err := h.Verify("dev1", "pw"); !errors.Is(err, ErrNotLoaded) {
		t.Errorf("Verify gave %v, want ErrNotLoaded", err)
	}

	dir := writeStore(t, 2048, map[string]string{"dev1": hash(t, "pw")}, false)
	s, err := Load(dir)
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	h.Set(s)
	if !h.Loaded() {
		t.Error("holder still reports not loaded after Set")
	}
	if _, _, err := h.Signing(); err != nil {
		t.Errorf("Signing after Set: %v", err)
	}
}
