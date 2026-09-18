package observability

import "sync/atomic"

// Readiness separates "the process is alive" from "the process can do its job".
//
// Getting this backwards is a classic outage amplifier: if liveness depended on
// Vault, a Vault restart would make Kubernetes kill every auth pod at once and
// turn a short dependency blip into a full outage. Liveness stays trivial;
// only readiness tracks Vault.
type Readiness struct {
	ready atomic.Bool
}

func (r *Readiness) Set(ok bool) {
	r.ready.Store(ok)
	if ok {
		VaultUp.Set(1)
		return
	}
	VaultUp.Set(0)
}

func (r *Readiness) Ready() bool { return r.ready.Load() }
