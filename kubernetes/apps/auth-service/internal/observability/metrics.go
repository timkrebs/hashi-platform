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

	VaultRequests = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "auth_vault_requests_total",
		Help: "Calls to Vault, by operation and outcome.",
	}, []string{"operation", "result"})

	VaultDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "auth_vault_request_duration_seconds",
		Help:    "Vault call duration. Signing is on the critical path of every login.",
		Buckets: prometheus.DefBuckets,
	}, []string{"operation"})

	// The same signal /readyz reports, as a number you can alert on.
	VaultUp = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "auth_vault_up",
		Help: "1 when the last Vault call succeeded, 0 otherwise.",
	})
)
