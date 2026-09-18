// Package httpapi wires the routes, middleware and server lifecycle.
package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"time"

	"github.com/timkrebs/auth-service/internal/observability"
)

type ctxKey int

const requestIDKey ctxKey = iota

// RequestID returns the correlation id for this request, or "" outside one.
func RequestID(ctx context.Context) string {
	id, _ := ctx.Value(requestIDKey).(string)
	return id
}

// withRequestID accepts an inbound X-Request-Id or mints one.
//
// Honouring the inbound header is what lets a trace survive across services:
// the middleware service can pass its id down and both sides' Loki lines line
// up on one value.
func withRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-Id")
		if id == "" || len(id) > 64 {
			b := make([]byte, 8)
			_, _ = rand.Read(b)
			id = hex.EncodeToString(b)
		}
		w.Header().Set("X-Request-Id", id)
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), requestIDKey, id)))
	})
}

// statusRecorder captures the status code, which ResponseWriter does not expose.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

// observe logs and measures one request.
//
// The route label is the registered pattern, never r.URL.Path: a path label
// would create a new Prometheus time series per distinct URL, which is how
// monitoring takes itself down.
func observe(log *slog.Logger, route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(rec, r)

		elapsed := time.Since(start)
		observability.HTTPDuration.WithLabelValues(r.Method, route).Observe(elapsed.Seconds())
		observability.HTTPRequests.WithLabelValues(r.Method, route, statusClass(rec.status)).Inc()

		log.LogAttrs(r.Context(), levelFor(rec.status), "request",
			slog.String("method", r.Method),
			slog.String("route", route),
			slog.Int("status", rec.status),
			slog.Duration("duration", elapsed),
			slog.String("request_id", RequestID(r.Context())),
			// Deliberately no username, no token, no Authorization header --
			// logs land in Loki and are read by more people than the service is.
		)
	})
}

func levelFor(status int) slog.Level {
	switch {
	case status >= 500:
		return slog.LevelError
	case status >= 400:
		return slog.LevelWarn
	default:
		return slog.LevelInfo
	}
}

// statusClass keeps the label cardinality at five values instead of dozens.
func statusClass(status int) string {
	switch {
	case status < 200:
		return "1xx"
	case status < 300:
		return "2xx"
	case status < 400:
		return "3xx"
	case status < 500:
		return "4xx"
	default:
		return "5xx"
	}
}

// recoverPanic turns a panic into a 500 instead of killing the process.
//
// net/http would already recover per connection, but it does so silently and
// writes nothing back -- the caller sees a dropped connection and no log line.
func recoverPanic(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				log.Error("panic recovered",
					slog.Any("panic", v),
					slog.String("request_id", RequestID(r.Context())))
				writeError(w, http.StatusInternalServerError, "internal_error", "unexpected error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
