package httpapi

import (
	"io"
	"net/http"

	"github.com/dripadvisor/backend/internal/gemini"
)

const maxAnalyzeBytes = 8 << 20 // 8 MB

// handleAnalyzeGarment runs Gemini vision on an uploaded photo and returns
// best-effort {name, brand, category, color_primary, tags}. iOS uses this to
// pre-fill the wardrobe form so the user has nothing to type.
func handleAnalyzeGarment(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Gemini == nil {
			writeError(w, http.StatusServiceUnavailable, "analysis unavailable")
			return
		}
		if err := r.ParseMultipartForm(maxAnalyzeBytes); err != nil {
			writeError(w, http.StatusBadRequest, "multipart parse failed")
			return
		}
		f, hdr, err := r.FormFile("file")
		if err != nil {
			writeError(w, http.StatusBadRequest, "file field required")
			return
		}
		defer f.Close()
		if hdr.Size > maxAnalyzeBytes {
			writeError(w, http.StatusRequestEntityTooLarge, "max 8MB")
			return
		}
		ct := hdr.Header.Get("Content-Type")
		if ct == "" {
			ct = "image/jpeg"
		}
		data, err := io.ReadAll(f)
		if err != nil {
			writeError(w, http.StatusBadRequest, "read failed")
			return
		}
		result, err := d.Gemini.AnalyzeGarment(r.Context(), gemini.ReferenceImage{
			MIMEType: ct, Data: data,
		})
		if err != nil {
			writeError(w, http.StatusBadGateway, err.Error())
			return
		}
		writeJSON(w, http.StatusOK, result)
	}
}
