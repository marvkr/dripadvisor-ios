package httpapi

import (
	"fmt"
	"io"
	"net/http"

	"github.com/dripadvisor/backend/internal/auth"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

const (
	maxAvatarBytes = 6 << 20 // 6 MB
	avatarKeyFmt   = "avatars/%s.jpg"
)

// handleUploadAvatar accepts a multipart/form-data POST with a "file" field
// (JPEG/PNG). Writes to S3 at avatars/{user_id}.jpg, updates
// users.avatar_url to the canonical fetch endpoint, returns {avatar_url}.
func handleUploadAvatar(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		if err := r.ParseMultipartForm(maxAvatarBytes); err != nil {
			writeError(w, http.StatusBadRequest, "multipart parse failed")
			return
		}
		f, hdr, err := r.FormFile("file")
		if err != nil {
			writeError(w, http.StatusBadRequest, "file field required")
			return
		}
		defer f.Close()
		if hdr.Size > maxAvatarBytes {
			writeError(w, http.StatusRequestEntityTooLarge, "max 6MB")
			return
		}
		ct := hdr.Header.Get("Content-Type")
		if ct != "image/jpeg" && ct != "image/png" {
			writeError(w, http.StatusUnsupportedMediaType, "jpeg or png only")
			return
		}
		key := fmt.Sprintf(avatarKeyFmt, uid)
		if err := d.Storage.Put(r.Context(), key, f, ct); err != nil {
			writeError(w, http.StatusInternalServerError, "storage put failed")
			return
		}
		url := "/me/avatar"
		if err := d.Users.SetAvatarURL(r.Context(), uid, url); err != nil {
			writeError(w, http.StatusInternalServerError, "db update failed")
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"avatar_url": url})
	}
}

// handleGetAvatar streams the caller's avatar bytes from S3. 404 when absent.
func handleGetAvatar(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		key := fmt.Sprintf(avatarKeyFmt, uid)
		stream, ct, err := d.Storage.Get(r.Context(), key)
		if err != nil {
			writeError(w, http.StatusNotFound, "no avatar")
			return
		}
		defer stream.Close()
		if ct == "" {
			ct = "image/jpeg"
		}
		w.Header().Set("Content-Type", ct)
		w.Header().Set("Cache-Control", "private, max-age=300")
		_, _ = io.Copy(w, stream)
	}
}

// handleGetUserAvatar streams the requested user's avatar by ID. Useful for
// chat rows / participant lists. No auth on the resource itself yet — bytes
// are opaque + addressed by UUID. Tighten later if needed.
func handleGetUserAvatar(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		idStr := chi.URLParam(r, "id")
		if _, err := uuid.Parse(idStr); err != nil {
			writeError(w, http.StatusBadRequest, "bad user id")
			return
		}
		key := fmt.Sprintf(avatarKeyFmt, idStr)
		stream, ct, err := d.Storage.Get(r.Context(), key)
		if err != nil {
			writeError(w, http.StatusNotFound, "no avatar")
			return
		}
		defer stream.Close()
		if ct == "" {
			ct = "image/jpeg"
		}
		w.Header().Set("Content-Type", ct)
		w.Header().Set("Cache-Control", "public, max-age=300")
		_, _ = io.Copy(w, stream)
	}
}
