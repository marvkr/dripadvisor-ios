package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/dripadvisor/backend/internal/auth"
	"github.com/dripadvisor/backend/internal/gemini"
)

// Try-on is synchronous in v1: client uploads body + garment, server calls
// Gemini Nano Banana Pro, persists composite to R2, returns URL. Body bytes
// stay in memory only — never written to disk or storage. Locked decision per
// README "Sensitive data — privacy tiers".

type tryOnReq struct {
	// BodyPhotoBase64 is the user's transient avatar / full-body reference.
	// Base64-encoded JPEG/PNG. Never persisted server-side.
	BodyPhotoBase64 string `json:"body_photo_base64"`
	BodyMIME        string `json:"body_mime"` // "image/jpeg" or "image/png"

	// One of: garment image (base64) inline, OR a wardrobe item id already
	// uploaded to R2 (server fetches via Wardrobe.ImageURL).
	GarmentBase64 string    `json:"garment_base64,omitempty"`
	GarmentMIME   string    `json:"garment_mime,omitempty"`
	WardrobeID    uuid.UUID `json:"wardrobe_id,omitempty"`

	Occasion string `json:"occasion,omitempty"`
}

type tryOnResp struct {
	CompositeURL string    `json:"composite_url"`
	GeneratedAt  time.Time `json:"generated_at"`
}

// handleTryOn POST /v1/tryon — synchronous compositing.
func handleTryOn(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := auth.UserID(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "no session")
			return
		}
		if d.Gemini == nil || d.Storage == nil {
			writeError(w, http.StatusServiceUnavailable, "try-on not configured")
			return
		}

		var req tryOnReq
		if err := json.NewDecoder(io.LimitReader(r.Body, 24<<20)).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}

		body, err := decodeBodyPhoto(req)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
		defer cancel()

		garment, err := resolveGarment(ctx, d, uid, req)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}

		composite, err := d.Gemini.ComposeOutfit(ctx, body, []gemini.ReferenceImage{garment}, req.Occasion)
		if err != nil {
			slog.WarnContext(ctx, "gemini compose failed", "err", err.Error(), "user", uid.String())
			writeError(w, http.StatusBadGateway, "compose failed")
			return
		}

		url, err := uploadComposite(ctx, d, uid, composite)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "upload failed")
			return
		}

		writeJSON(w, http.StatusOK, tryOnResp{CompositeURL: url, GeneratedAt: time.Now().UTC()})
	}
}

func decodeBodyPhoto(req tryOnReq) (gemini.ReferenceImage, error) {
	if req.BodyPhotoBase64 == "" {
		return gemini.ReferenceImage{}, errors.New("body_photo_base64 required")
	}
	mime := strings.TrimSpace(req.BodyMIME)
	if mime == "" {
		mime = "image/jpeg"
	}
	data, err := base64.StdEncoding.DecodeString(req.BodyPhotoBase64)
	if err != nil {
		return gemini.ReferenceImage{}, errors.New("invalid base64 body photo")
	}
	if len(data) == 0 {
		return gemini.ReferenceImage{}, errors.New("empty body photo")
	}
	return gemini.ReferenceImage{MIMEType: mime, Data: data}, nil
}

func resolveGarment(ctx context.Context, d *Deps, uid uuid.UUID, req tryOnReq) (gemini.ReferenceImage, error) {
	if req.GarmentBase64 != "" {
		mime := strings.TrimSpace(req.GarmentMIME)
		if mime == "" {
			mime = "image/png"
		}
		data, err := base64.StdEncoding.DecodeString(req.GarmentBase64)
		if err != nil {
			return gemini.ReferenceImage{}, errors.New("invalid base64 garment")
		}
		return gemini.ReferenceImage{MIMEType: mime, Data: data}, nil
	}
	if req.WardrobeID == uuid.Nil {
		return gemini.ReferenceImage{}, errors.New("garment_base64 or wardrobe_id required")
	}
	return fetchGarmentFromR2(ctx, d, uid, req.WardrobeID)
}

func fetchGarmentFromR2(ctx context.Context, _ *Deps, _ uuid.UUID, _ uuid.UUID) (gemini.ReferenceImage, error) {
	// v1 lookup-from-wardrobe path is not yet wired; clients send garment
	// bytes inline. Stub here so future PR can implement R2 fetch + DB lookup
	// without changing the public contract.
	_ = ctx
	return gemini.ReferenceImage{}, errors.New("wardrobe lookup not yet supported; send garment_base64 inline")
}

func uploadComposite(ctx context.Context, d *Deps, uid uuid.UUID, png []byte) (string, error) {
	key := fmt.Sprintf("tryons/%s/%s.png", uid.String(), uuid.New().String())
	if err := d.Storage.Put(ctx, key, bytes.NewReader(png), "image/png"); err != nil {
		return "", err
	}
	return d.Storage.PublicURL(key), nil
}
