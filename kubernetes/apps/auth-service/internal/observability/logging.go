// Package observability holds logging, metrics and readiness.
package observability

import (
	"log/slog"
	"os"
	"strings"
)

// NewLogger returns a JSON logger on stdout.
//
// JSON because Alloy ships stdout to Loki verbatim; structured fields stay
// queryable there, a formatted message does not. Nothing is written to a file:
// the container's root filesystem is read-only and a log file inside a pod is
// lost on restart anyway.
func NewLogger(level string) *slog.Logger {
	var l slog.Level
	switch strings.ToLower(level) {
	case "debug":
		l = slog.LevelDebug
	case "warn":
		l = slog.LevelWarn
	case "error":
		l = slog.LevelError
	default:
		l = slog.LevelInfo
	}

	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: l,
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			// Loki and Grafana both expect "timestamp"; slog's default key is "time".
			if a.Key == slog.TimeKey {
				a.Key = "timestamp"
			}
			return a
		},
	}))
}
