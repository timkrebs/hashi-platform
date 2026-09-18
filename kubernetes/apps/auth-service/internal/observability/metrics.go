package observability

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// Metrics scraped by the ServiceMonitor in deploy/.
//
// Every label here is bounded. A label carrying a username or a token ID would
// create one time series per value and eventually take Prometheus down -- which
// is why the route label is the registered pattern, never the request path.
var (
	HTTPRequests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "auth_http_requests_total",
		Help: "HTTP requests by route and status class.",
	}, []string{"method", "route", "status"})

	HTTPDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "auth_http_request_duration_seconds",
		Help:    "HTTP request duration by route.",
		Buckets: prometheus.DefBuckets,
	}, []string{"method", "route"})

	TokensIssued = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "auth_tokens_issued_total",
		Help: "Tokens issued, by outcome.",
	}, []string{"result"})

	SecretLoads = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "auth_secret_loads_total",
		Help: "Attempts to read the synced secret, by outcome. A rising error count with a loaded secret means rotation is failing silently.",
	}, []string{"result"})

	// The same signal /readyz reports, as a number you can alert on.
	SecretLoaded = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "auth_secret_loaded",
		Help: "1 when the Vault Secrets Operator has synced a usable secret, 0 otherwise.",
	})
)

// init publishes the series whose label values are known in advance.
//
// A CounterVec emits nothing at all until some label combination is touched --
// not even a # TYPE line. On a freshly started pod that means
// rate(auth_tokens_issued_total{result="denied"}[5m]) returns *empty*, not
// zero, so a panel shows "No data" and an alert on it never fires because
// there is nothing to compare against.
//
// Only bounded, known-in-advance label sets belong here. Routes and status
// classes are left to appear on first use: pre-seeding them would mean
// guessing which combinations exist.
func init() {
	for _, result := range []string{"ok", "denied", "error"} {
		TokensIssued.WithLabelValues(result)
	}
	for _, result := range []string{"ok", "error"} {
		SecretLoads.WithLabelValues(result)
	}
	SecretLoaded.Set(0)
}
