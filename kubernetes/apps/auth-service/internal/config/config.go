// Package config turns the environment into a validated, typed struct.
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config is everything the service needs at startup. There are no defaults for
// values that cannot be guessed safely -- the service refuses to start rather
// than run with a plausible-looking wrong one.
type Config struct {
	HTTPAddr       string
	AdminAddr      string
	VaultAddr      string
	VaultNamespace string
	VaultTokenPath string
	TransitMount   string
	SigningKey     string
	UserpassMount  string
	Issuer         string
	Audience       string
	TokenTTL       time.Duration
	ShutdownGrace  time.Duration
	TokenRefresh   time.Duration
	LogLevel       string
}

// Load reads the environment and validates it.
func Load() (Config, error) {
	c := Config{
		HTTPAddr: env("HTTP_ADDR", ":8080"),
		// Metrics and health. Separate listener, never published outside
		// the cluster -- see internal/httpapi/server.go.
		AdminAddr:      env("ADMIN_ADDR", ":9090"),
		VaultAddr:      env("VAULT_ADDR", "https://vault.vault.svc:8200"),
		VaultNamespace: env("VAULT_NAMESPACE", "hp-dev-backend"),
		// Written by the Vault Agent sidecar, not by us. See deploy/deployment.yaml.
		VaultTokenPath: env("VAULT_TOKEN_PATH", "/vault/secrets/token"),
		TransitMount:   env("VAULT_TRANSIT_MOUNT", "transit"),
		SigningKey:     env("VAULT_SIGNING_KEY", "auth-service-jwt"),
		UserpassMount:  env("VAULT_USERPASS_MOUNT", "userpass"),
		Issuer:         env("TOKEN_ISSUER", "https://auth-service.auth-service.svc.cluster.local"),
		Audience:       env("TOKEN_AUDIENCE", "hashi-platform"),
		LogLevel:       env("LOG_LEVEL", "info"),
	}

	var err error
	if c.TokenTTL, err = envDuration("TOKEN_TTL", 15*time.Minute); err != nil {
		return c, err
	}
	// Must stay below the Deployment's terminationGracePeriodSeconds, or the
	// grace period is decorative and in-flight requests are cut off by SIGKILL.
	if c.ShutdownGrace, err = envDuration("SHUTDOWN_GRACE", 20*time.Second); err != nil {
		return c, err
	}
	// How often the Vault token file is re-read. The agent rewrites it on
	// renewal; without re-reading, the service keeps using a token that has
	// already expired and every sign call starts failing with 403.
	if c.TokenRefresh, err = envDuration("VAULT_TOKEN_REFRESH", 30*time.Second); err != nil {
		return c, err
	}

	return c, c.validate()
}

func (c Config) validate() error {
	// TrimSpace, not == "": a whitespace-only issuer passes an empty check and
	// then lands verbatim in every token's iss claim, where it fails every
	// verifier for a reason nobody will guess.
	if strings.TrimSpace(c.Issuer) == "" {
		return fmt.Errorf("TOKEN_ISSUER must not be blank: it ends up in every token's iss claim")
	}
	if c.TokenTTL <= 0 {
		return fmt.Errorf("TOKEN_TTL must be positive, got %s", c.TokenTTL)
	}
	if c.TokenTTL > time.Hour {
		return fmt.Errorf("TOKEN_TTL %s is longer than an hour; these tokens cannot be revoked, so keep them short", c.TokenTTL)
	}
	return nil
}

func env(key, def string) string {
	// Trimmed because these often come from a file or a YAML block scalar,
	// where a trailing newline is invisible and breaks exact comparisons.
	if v, ok := os.LookupEnv(key); ok && strings.TrimSpace(v) != "" {
		return strings.TrimSpace(v)
	}
	return def
}

func envDuration(key string, def time.Duration) (time.Duration, error) {
	raw, ok := os.LookupEnv(key)
	if !ok || raw == "" {
		return def, nil
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		// Accept a bare number of seconds too, which is what people type.
		if n, convErr := strconv.Atoi(raw); convErr == nil {
			return time.Duration(n) * time.Second, nil
		}
		return 0, fmt.Errorf("%s=%q is not a duration: %w", key, raw, err)
	}
	return d, nil
}
