// Package imaging wraps the self-hosted rembg HTTP server.
// rembg = U²-Net / BiRefNet / Bria RMBG family for background removal,
// producing transparent-PNG cutouts. We use it for scraped ecommerce
// shots (Lulu, Uniqlo, Zara) where Apple Vision on-device fails — see
// CLAUDE.md.
package imaging

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"time"
)

type Rembg struct {
	baseURL string
	client  *http.Client
}

func NewRembg(baseURL string) *Rembg {
	return &Rembg{
		baseURL: baseURL,
		client:  &http.Client{Timeout: 30 * time.Second},
	}
}

// Available pings the rembg server. Used at startup so we can log a warning
// if the container isn't reachable, instead of failing first user request.
func (r *Rembg) Available(ctx context.Context) bool {
	if r == nil || r.baseURL == "" {
		return false
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, r.baseURL+"/api/ping", nil)
	if err != nil {
		return false
	}
	resp, err := r.client.Do(req)
	if err != nil {
		return false
	}
	defer func() { _ = resp.Body.Close() }()
	return resp.StatusCode == http.StatusOK
}

// Remove POSTs an image to rembg and returns the transparent-PNG bytes.
// Caller is responsible for storing the result (R2/MinIO) and surfacing
// the URL. Inference is CPU-bound, ~3-5s per image.
func (r *Rembg) Remove(ctx context.Context, image []byte, filename string) ([]byte, error) {
	if r == nil || r.baseURL == "" {
		return nil, fmt.Errorf("rembg not configured")
	}
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		return nil, fmt.Errorf("multipart: %w", err)
	}
	if _, err := part.Write(image); err != nil {
		return nil, fmt.Errorf("multipart write: %w", err)
	}
	if err := writer.Close(); err != nil {
		return nil, fmt.Errorf("multipart close: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.baseURL+"/api/remove", body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := r.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("rembg call: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("rembg status %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 10<<20))
}
