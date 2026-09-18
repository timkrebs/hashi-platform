package secrets

import (
	"crypto/rsa"
	"errors"
	"sync/atomic"
)

// ErrNotLoaded is returned before the operator has written the Secret.
//
// The pod can start before the VaultStaticSecret is synced -- Argo CD applies
// the Deployment and the CR in the same wave, and the operator needs a moment
// to authenticate and fetch. Crashing through that window would hide the real
// cause behind a restart loop, so the service starts, answers /healthz, and
// reports itself unready until the files appear.
var ErrNotLoaded = errors.New("secrets not loaded yet")

// Holder makes a Store swappable while the process runs.
type Holder struct {
	store atomic.Pointer[Store]
}

func (h *Holder) Set(s *Store) { h.store.Store(s) }

func (h *Holder) Loaded() bool { return h.store.Load() != nil }

// Signing returns the key and its id, or ErrNotLoaded.
func (h *Holder) Signing() (*rsa.PrivateKey, string, error) {
	s := h.store.Load()
	if s == nil {
		return nil, "", ErrNotLoaded
	}
	return s.key, s.keyID, nil
}

// Verify checks a password, or reports ErrNotLoaded.
func (h *Holder) Verify(username, password string) error {
	s := h.store.Load()
	if s == nil {
		return ErrNotLoaded
	}
	return s.Verify(username, password)
}
