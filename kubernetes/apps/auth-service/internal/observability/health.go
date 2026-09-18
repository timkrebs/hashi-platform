package observability

import "sync/atomic"

// Readiness separates "the process is alive" from "the process can do its job".
//
// Getting this backwards is a classic outage amplifier: if liveness depended on
// the synced secret, a sync problem would make Kubernetes restart every auth
// pod instead of taking them out of rotation. Liveness stays trivial; only
// readiness tracks the secret.
type Readiness struct {
	ready atomic.Bool
}

func (r *Readiness) Set(ok bool) {
	r.ready.Store(ok)
	if ok {
		SecretLoaded.Set(1)
		return
	}
	SecretLoaded.Set(0)
}

func (r *Readiness) Ready() bool { return r.ready.Load() }
