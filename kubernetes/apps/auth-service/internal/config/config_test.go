package config

import (
	"strings"
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	c, err := Load()
	if err != nil {
		t.Fatalf("load with no environment: %v", err)
	}
	if c.HTTPAddr != ":8080" || c.AdminAddr != ":9090" {
		t.Errorf("unexpected defaults: %+v", c)
	}
	if c.TokenTTL != 15*time.Minute {
		t.Errorf("TokenTTL = %s, want 15m", c.TokenTTL)
	}
	// The grace period has to leave room inside the pod's termination grace.
	if c.ShutdownGrace >= 40*time.Second {
		t.Errorf("ShutdownGrace %s must stay below terminationGracePeriodSeconds (40s)", c.ShutdownGrace)
	}
}

// A token that cannot be revoked must not be long-lived. Catching this at
// startup is the difference between a refused rollout and a day-long leak.
func TestLoadRejectsOverlongTTL(t *testing.T) {
	t.Setenv("TOKEN_TTL", "24h")
	_, err := Load()
	if err == nil {
		t.Fatal("expected TOKEN_TTL=24h to be rejected")
	}
	if !strings.Contains(err.Error(), "revoke") {
		t.Errorf("error should explain why: %v", err)
	}
}

func TestLoadRejectsBadValues(t *testing.T) {
	tests := []struct{ key, value string }{
		{"TOKEN_TTL", "0s"},
		{"TOKEN_TTL", "-5m"},
		{"SHUTDOWN_GRACE", "not-a-duration"},
	}
	for _, tc := range tests {
		t.Run(tc.key+"="+tc.value, func(t *testing.T) {
			t.Setenv(tc.key, tc.value)
			if _, err := Load(); err == nil {
				t.Errorf("accepted %s=%q", tc.key, tc.value)
			}
		})
	}
}

// A blank environment variable falls back to the default rather than being
// rejected -- a YAML block scalar or a mounted file easily produces one, and
// failing to start over invisible whitespace is worse than using the default.
// The blank check in validate() stays as a guard for programmatic construction.
func TestBlankEnvFallsBackToDefault(t *testing.T) {
	t.Setenv("TOKEN_ISSUER", "   ")
	c, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if c.Issuer != "https://auth-service.auth-service.svc.cluster.local" {
		t.Errorf("Issuer = %q, want the default", c.Issuer)
	}
}

// A trailing newline is invisible and breaks exact comparisons downstream.
func TestValuesAreTrimmed(t *testing.T) {
	t.Setenv("SECRETS_DIR", "/etc/auth-service/secrets\n")
	c, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if c.SecretsDir != "/etc/auth-service/secrets" {
		t.Errorf("SecretsDir = %q, want it trimmed", c.SecretsDir)
	}
}

// People type "30" when they mean thirty seconds. Accepting it is kinder than
// failing, as long as it is unambiguous.
func TestBareSecondsAreAccepted(t *testing.T) {
	t.Setenv("SHUTDOWN_GRACE", "30")
	c, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if c.ShutdownGrace != 30*time.Second {
		t.Errorf("ShutdownGrace = %s, want 30s", c.ShutdownGrace)
	}
}
