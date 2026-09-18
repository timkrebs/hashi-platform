package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/timkrebs/auth-service/internal/auth"
	"github.com/timkrebs/auth-service/internal/observability"
)

// Server owns two listeners.
//
// Splitting them is deliberate. Metrics expose internal timing and request
// volumes, and /readyz reveals dependency state -- neither belongs on the port
// that serves untrusted callers. Two listeners mean a NetworkPolicy or an
// ingress can publish one and keep the other cluster-internal, without relying
// on path filtering somewhere upstream.
type Server struct {
	auth  *auth.Service
	log   *slog.Logger
	ready *observability.Readiness

	public *http.Server
	admin  *http.Server
}

func New(a *auth.Service, log *slog.Logger, ready *observability.Readiness, publicAddr, adminAddr string) *Server {
	s := &Server{auth: a, log: log, ready: ready}

	public := http.NewServeMux()
	public.Handle("POST /v1/token", observe(log, "/v1/token", http.HandlerFunc(s.handleToken)))
	public.Handle("GET /.well-known/jwks.json", observe(log, "/.well-known/jwks.json", http.HandlerFunc(s.handleJWKS)))

	admin := http.NewServeMux()
	admin.Handle("GET /metrics", promhttp.Handler())
	admin.HandleFunc("GET /healthz", s.handleHealthz)
	admin.HandleFunc("GET /readyz", s.handleReadyz)

	s.public = &http.Server{
		Addr:    publicAddr,
		Handler: recoverPanic(log, withRequestID(public)),
		// ReadHeaderTimeout is the one that matters against Slowloris: without
		// it a client can hold a connection open indefinitely by trickling
		// header bytes.
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	s.admin = &http.Server{
		Addr:              adminAddr,
		Handler:           admin,
		ReadHeaderTimeout: 5 * time.Second,
	}

	return s
}

// Start runs both listeners until one fails or ctx is cancelled.
func (s *Server) Start(ctx context.Context) error {
	errs := make(chan error, 2)

	go func() {
		s.log.Info("public listener started", slog.String("addr", s.public.Addr))
		if err := s.public.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errs <- err
		}
	}()
	go func() {
		s.log.Info("admin listener started", slog.String("addr", s.admin.Addr))
		if err := s.admin.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errs <- err
		}
	}()

	select {
	case <-ctx.Done():
		return nil
	case err := <-errs:
		return err
	}
}

// Shutdown stops accepting connections and waits for in-flight requests.
//
// Public first: it is the one with real callers. The admin listener stays up a
// moment longer so the final /readyz probe still gets an answer instead of a
// connection refused, which reads as a crash in the events.
func (s *Server) Shutdown(grace time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), grace)
	defer cancel()

	if err := s.public.Shutdown(ctx); err != nil {
		return err
	}
	return s.admin.Shutdown(ctx)
}
