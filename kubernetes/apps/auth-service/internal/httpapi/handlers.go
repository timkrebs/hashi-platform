package httpapi

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/timkrebs/auth-service/internal/auth"
)

type tokenRequest struct {
	Username string   `json:"username"`
	Password string   `json:"password"`
	Scopes   []string `json:"scope,omitempty"`
}

type tokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
}

type errorResponse struct {
	Error       string `json:"error"`
	Description string `json:"error_description,omitempty"`
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	// These responses carry credentials; no shared cache should keep them.
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func writeError(w http.ResponseWriter, status int, code, description string) {
	writeJSON(w, status, errorResponse{Error: code, Description: description})
}

// handleToken exchanges credentials for a signed JWT.
func (s *Server) handleToken(w http.ResponseWriter, r *http.Request) {
	// Cap the body: without a limit an unauthenticated caller can stream
	// gigabytes into json.Decode.
	var req tokenRequest
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "body must be JSON with username and password")
		return
	}
	if req.Username == "" || req.Password == "" {
		writeError(w, http.StatusBadRequest, "invalid_request", "username and password are required")
		return
	}

	token, expiresAt, err := s.auth.Issue(req.Username, req.Password, req.Scopes)
	switch {
	case errors.Is(err, auth.ErrInvalidCredentials):
		// The same answer for an unknown user and a wrong password. Telling
		// them apart would turn this into a username oracle.
		writeError(w, http.StatusUnauthorized, "invalid_grant", "invalid username or password")
		return
	case err != nil:
		// Almost always the synced secret not being there yet. Log the detail,
		// return none of it.
		s.log.Error("token issue failed",
			slog.String("error", err.Error()),
			slog.String("request_id", RequestID(r.Context())))
		writeError(w, http.StatusServiceUnavailable, "temporarily_unavailable", "cannot issue tokens right now")
		return
	}

	writeJSON(w, http.StatusOK, tokenResponse{
		AccessToken: token,
		TokenType:   "Bearer",
		ExpiresIn:   int(time.Until(expiresAt).Seconds()),
	})
}

// handleJWKS publishes the public keys.
//
// This is what makes the architecture scale: every other service verifies
// tokens locally against these keys and never calls the auth service on the
// request path. An auth service that has to be asked about every token is a
// single point of failure for the whole cluster.
func (s *Server) handleJWKS(w http.ResponseWriter, _ *http.Request) {
	keys, err := s.auth.JWKS()
	if err != nil {
		s.log.Error("jwks unavailable", slog.String("error", err.Error()))
		writeError(w, http.StatusServiceUnavailable, "temporarily_unavailable", "keys unavailable")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	// Public material, and verifiers poll it. A short cache keeps the load off
	// Vault without delaying a rotation for long.
	w.Header().Set("Cache-Control", "public, max-age=300")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]any{"keys": keys})
}

// handleHealthz is liveness: is this process running? Nothing else.
func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

// handleReadyz is readiness: can this process actually issue tokens?
//
// This is where the Vault dependency belongs. An unready pod is removed from
// the Service endpoints; an unhealthy one is restarted. Vault being briefly
// unavailable should do the first, never the second.
func (s *Server) handleReadyz(w http.ResponseWriter, _ *http.Request) {
	if !s.ready.Ready() {
		writeError(w, http.StatusServiceUnavailable, "not_ready", "synced secret not available")
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ready"))
}
