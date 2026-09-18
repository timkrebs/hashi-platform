// Command server runs the auth service.
//
// It issues short-lived RS256 JWTs. The signing key and the user list come from
// a Kubernetes Secret that the Vault Secrets Operator syncs out of Vault; this
// process never talks to Vault itself. A Vault outage therefore does not stop
// logins -- and a compromised pod holds a real signing key, which is the other
// half of that trade.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/timkrebs/auth-service/internal/auth"
	"github.com/timkrebs/auth-service/internal/config"
	"github.com/timkrebs/auth-service/internal/httpapi"
	"github.com/timkrebs/auth-service/internal/observability"
	"github.com/timkrebs/auth-service/internal/secrets"
)

func main() {
	if err := run(); err != nil {
		slog.Error("fatal", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	log := observability.NewLogger(cfg.LogLevel)
	slog.SetDefault(log)
	log.Info("starting",
		slog.String("secrets_dir", cfg.SecretsDir),
		slog.Duration("token_ttl", cfg.TokenTTL))

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	holder := &secrets.Holder{}
	svc := auth.NewService(holder, holder, auth.Options{
		Issuer:   cfg.Issuer,
		Audience: cfg.Audience,
		TokenTTL: cfg.TokenTTL,
	})

	ready := &observability.Readiness{}
	srv := httpapi.New(svc, log, ready, cfg.HTTPAddr, cfg.AdminAddr)

	errCh := make(chan error, 1)
	go func() { errCh <- srv.Start(ctx) }()

	// The listeners come up before the secret is read.
	//
	// Argo CD applies the Deployment and the VaultStaticSecret together, and
	// the operator needs a moment to authenticate and fetch. Blocking here
	// would leave /healthz unanswered through that window, the startup probe
	// would read that as a dead process, and the pod would restart in a loop
	// whose cause never reaches the log.
	go loadSecrets(ctx, cfg, holder, ready, log)

	select {
	case err := <-errCh:
		if err != nil {
			return err
		}
	case <-ctx.Done():
		log.Info("shutdown signal received")
	}

	// Report unready at once: the endpoint controller removes this pod while
	// the grace period drains what is already in flight.
	ready.Set(false)
	return srv.Shutdown(cfg.ShutdownGrace)
}

// loadSecrets retries until the mounted directory is readable.
//
// It keeps running afterwards. The operator restarts this Deployment on a
// rotation (rolloutRestartTargets), so a reload is not the normal path -- but
// re-reading costs nothing and covers the case where the Secret is updated in
// place without a restart.
func loadSecrets(ctx context.Context, cfg config.Config, holder *secrets.Holder, ready *observability.Readiness, log *slog.Logger) {
	t := time.NewTicker(cfg.SecretsRetry)
	defer t.Stop()

	for {
		store, err := secrets.Load(cfg.SecretsDir)
		switch {
		case err != nil && !holder.Loaded():
			observability.SecretLoads.WithLabelValues("error").Inc()
			// Not an error yet: the operator may simply not have written it.
			log.Info("waiting for synced secret", slog.String("reason", err.Error()))
		case err != nil:
			observability.SecretLoads.WithLabelValues("error").Inc()
			// It was there and now is not, or it became unreadable. Keep the
			// key already in memory rather than dropping into a failed state.
			log.Warn("secret reload failed, keeping the loaded one", slog.String("error", err.Error()))
		default:
			observability.SecretLoads.WithLabelValues("ok").Inc()
			first := !holder.Loaded()
			holder.Set(store)
			ready.Set(true)
			if first {
				log.Info("secret loaded", slog.String("kid", store.KeyID()))
			}
		}

		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}
