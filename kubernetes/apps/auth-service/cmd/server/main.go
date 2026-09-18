// Command server runs the auth service.
//
// It issues short-lived RS256 JWTs. Credentials are checked against Vault's
// userpass auth, and the signature is produced by Vault's Transit engine -- the
// private key is generated inside Vault and never leaves it, so this process
// cannot mint a token once its Vault token is gone.
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
	"github.com/timkrebs/auth-service/internal/vault"
)

func main() {
	if err := run(); err != nil {
		// The logger may not exist yet at this point, so use the default one.
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
		slog.String("vault_addr", cfg.VaultAddr),
		slog.String("vault_namespace", cfg.VaultNamespace),
		slog.Duration("token_ttl", cfg.TokenTTL))

	// SIGTERM arrives first, then terminationGracePeriodSeconds, then SIGKILL.
	// Cancelling ctx here is what lets in-flight requests finish.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	vc := vault.New(cfg.VaultAddr, cfg.VaultNamespace, cfg.VaultTokenPath, log)

	svc := auth.NewService(vc, vc, vc, auth.Options{
		TransitMount:  cfg.TransitMount,
		SigningKey:    cfg.SigningKey,
		UserpassMount: cfg.UserpassMount,
		Issuer:        cfg.Issuer,
		Audience:      cfg.Audience,
		TokenTTL:      cfg.TokenTTL,
	})

	ready := &observability.Readiness{}
	srv := httpapi.New(svc, log, ready, cfg.HTTPAddr, cfg.AdminAddr)

	errCh := make(chan error, 1)
	go func() { errCh <- srv.Start(ctx) }()

	// The Vault bootstrap runs in the background, and the listeners are already
	// up before it starts.
	//
	// The order matters: the Agent sidecar needs a moment to log in and write
	// the token, and blocking here would leave /healthz unanswered for that
	// whole window. The startup probe would read that as a dead process and
	// kill the pod -- a restart loop whose cause is nowhere in the logs,
	// because the process never got far enough to log anything.
	//
	// /readyz stays false until Vault actually answers, so the pod takes no
	// traffic it cannot serve.
	go func() {
		if err := waitForToken(ctx, vc, log); err != nil {
			return // context cancelled; shutdown is already under way
		}
		go vc.WatchToken(ctx, cfg.TokenRefresh)

		if err := svc.Warm(ctx); err != nil {
			log.Warn("initial key fetch failed; staying unready", slog.String("error", err.Error()))
		} else {
			ready.Set(true)
			log.Info("ready")
		}
		pollReadiness(ctx, svc, ready, log)
	}()

	select {
	case err := <-errCh:
		if err != nil {
			return err
		}
	case <-ctx.Done():
		log.Info("shutdown signal received")
	}

	// Report unready immediately: the endpoint controller takes this pod out of
	// rotation while the grace period drains what is already in flight.
	ready.Set(false)
	return srv.Shutdown(cfg.ShutdownGrace)
}

// waitForToken blocks until the Agent sidecar has written the token file.
func waitForToken(ctx context.Context, vc *vault.Client, log *slog.Logger) error {
	const every = 2 * time.Second
	for {
		if err := vc.ReloadToken(); err == nil {
			return nil
		} else {
			log.Info("waiting for vault agent token", slog.String("reason", err.Error()))
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(every):
		}
	}
}

// pollReadiness keeps /readyz honest after startup.
func pollReadiness(ctx context.Context, svc *auth.Service, ready *observability.Readiness, log *slog.Logger) {
	t := time.NewTicker(15 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			checkCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			err := svc.Warm(checkCtx)
			cancel()
			if err != nil {
				log.Warn("readiness check failed", slog.String("error", err.Error()))
			}
			ready.Set(err == nil)
		}
	}
}
