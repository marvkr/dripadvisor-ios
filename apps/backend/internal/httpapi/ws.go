package httpapi

import (
	"net/http"
	"strings"

	"github.com/google/uuid"
)

// handleWS upgrades the HTTP connection to a WebSocket. Mounted OUTSIDE the
// chi auth middleware (so the 30s Timeout doesn't kill long-lived sockets),
// so this handler authenticates the request itself. Token may arrive as
// `Authorization: Bearer <jwt>` (iOS URLSessionWebSocketTask supports
// headers on upgrade) or `?token=<jwt>` (browser WebSocket API does not).
func handleWS(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Realtime == nil || d.Gateway == nil {
			writeError(w, http.StatusServiceUnavailable, "ws not configured")
			return
		}

		tok := bearerOrQueryToken(r)
		if tok == "" {
			writeError(w, http.StatusUnauthorized, "missing token")
			return
		}
		claims, err := d.Signer.Verify(tok)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "invalid token")
			return
		}
		uid, err := uuid.Parse(claims.Subject)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "bad sub")
			return
		}
		d.Gateway.ServeHTTP(w, r, uid)
	}
}

func bearerOrQueryToken(r *http.Request) string {
	if h := r.Header.Get("Authorization"); strings.HasPrefix(h, "Bearer ") {
		return strings.TrimPrefix(h, "Bearer ")
	}
	return r.URL.Query().Get("token")
}
