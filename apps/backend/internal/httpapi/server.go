package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"

	"github.com/dripadvisor/backend/internal/auth"
	"github.com/dripadvisor/backend/internal/db"
	"github.com/dripadvisor/backend/internal/gemini"
	"github.com/dripadvisor/backend/internal/storage"
)

// Deps holds the wiring that handlers need.
type Deps struct {
	Users    *db.UserRepo
	Wardrobe *db.WardrobeRepo
	Outfits  *db.OutfitRepo
	Apple    *auth.AppleVerifier
	Signer   *auth.Signer
	Gemini   *gemini.Client // optional; nil disables /v1/tryon
	Storage  *storage.Client
}

// NewRouter builds the chi router with all endpoints mounted.
func NewRouter(d *Deps) http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	})

	r.Post("/v1/auth/apple", handleAppleSignIn(d))

	r.Group(func(g chi.Router) {
		g.Use(auth.Middleware(d.Signer))

		g.Get("/v1/me", handleMe(d))
		g.Get("/v1/wardrobe", handleListWardrobe(d))
		g.Post("/v1/wardrobe", handleAddWardrobe(d))
		g.Post("/v1/wardrobe/{id}/worn", handleMarkWorn(d))
		g.Post("/v1/wardrobe/scrape", handleScrapeWardrobe(d))
		g.Delete("/v1/wardrobe/{id}", handleDeleteWardrobe(d))
		g.Get("/v1/outfits", handleListOutfits(d))
		g.Post("/v1/outfits", handleCreateOutfit(d))

		// /v1/tryon needs its own longer timeout — Gemini composites take
		// 5–30s; chi's Recoverer + Timeout middleware would kill the request
		// at the default 30s. Mount under a sub-router with bumped budget.
		g.Group(func(t chi.Router) {
			t.Use(middleware.Timeout(100 * time.Second))
			t.Post("/v1/tryon", handleTryOn(d))
		})
	})

	return r
}

// ----- Apple Sign In -----

type appleSignInReq struct {
	IdentityToken string `json:"identity_token"`
}

type appleSignInResp struct {
	Session   string    `json:"session"`
	ExpiresAt time.Time `json:"expires_at"`
	User      userDTO   `json:"user"`
}

func handleAppleSignIn(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req appleSignInReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.IdentityToken) == "" {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
		defer cancel()
		claims, err := d.Apple.Verify(ctx, req.IdentityToken)
		if err != nil {
			slog.WarnContext(ctx, "apple verify failed", "err", err.Error())
			writeError(w, http.StatusUnauthorized, "apple verify failed")
			return
		}
		user, err := d.Users.UpsertByAppleSub(ctx, claims.Subject, claims.Email)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "user upsert failed")
			return
		}
		tok, exp, err := d.Signer.Issue(user.ID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "sign session failed")
			return
		}
		writeJSON(w, http.StatusOK, appleSignInResp{
			Session:   tok,
			ExpiresAt: exp,
			User:      newUserDTO(user),
		})
	}
}

// ----- Me -----

func handleMe(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, ok := auth.UserID(r.Context())
		if !ok {
			writeError(w, http.StatusUnauthorized, "no session")
			return
		}
		u, err := d.Users.GetByID(r.Context(), uid)
		if err != nil {
			if errors.Is(err, db.ErrNotFound) {
				writeError(w, http.StatusNotFound, "user gone")
				return
			}
			writeError(w, http.StatusInternalServerError, "fetch failed")
			return
		}
		writeJSON(w, http.StatusOK, newUserDTO(u))
	}
}

// ----- Wardrobe -----

type wardrobeItemDTO struct {
	ID           uuid.UUID  `json:"id"`
	Name         string     `json:"name"`
	Brand        string     `json:"brand"`
	Category     string     `json:"category"`
	ImageURL     *string    `json:"image_url,omitempty"`
	SourceURL    *string    `json:"source_url,omitempty"`
	Tags         []string   `json:"tags"`
	ColorPrimary *string    `json:"color_primary,omitempty"`
	Source       string     `json:"source"`
	Size         *string    `json:"size,omitempty"`
	Material     *string    `json:"material,omitempty"`
	PricePaid    *float64   `json:"price_paid,omitempty"`
	RetailPrice  *float64   `json:"retail_price,omitempty"`
	Currency     *string    `json:"currency,omitempty"`
	LastWornAt   *time.Time `json:"last_worn_at,omitempty"`
	WearCount    int        `json:"wear_count"`
	CreatedAt    time.Time  `json:"created_at"`
}

type addWardrobeReq struct {
	Name         string   `json:"name"`
	Brand        string   `json:"brand"`
	Category     string   `json:"category"`
	ImageURL     *string  `json:"image_url,omitempty"`
	SourceURL    *string  `json:"source_url,omitempty"`
	Tags         []string `json:"tags,omitempty"`
	ColorPrimary *string  `json:"color_primary,omitempty"`
	Source       string   `json:"source,omitempty"`
	Size         *string  `json:"size,omitempty"`
	Material     *string  `json:"material,omitempty"`
	PricePaid    *float64 `json:"price_paid,omitempty"`
	RetailPrice  *float64 `json:"retail_price,omitempty"`
	Currency     *string  `json:"currency,omitempty"`
}

func handleListWardrobe(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		items, err := d.Wardrobe.ListByUser(r.Context(), uid, 200)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "list failed")
			return
		}
		out := make([]wardrobeItemDTO, 0, len(items))
		for _, i := range items {
			out = append(out, toWardrobeDTO(i))
		}
		writeJSON(w, http.StatusOK, map[string]any{"items": out})
	}
}

func handleAddWardrobe(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		var req addWardrobeReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		if !validCategory(req.Category) {
			writeError(w, http.StatusBadRequest, "invalid category")
			return
		}
		source := req.Source
		if source == "" {
			source = "owned"
		}
		if source != "owned" && source != "wishlist" {
			writeError(w, http.StatusBadRequest, "invalid source")
			return
		}
		item := &db.WardrobeItem{
			UserID:       uid,
			Name:         strings.TrimSpace(req.Name),
			Brand:        strings.TrimSpace(req.Brand),
			Category:     req.Category,
			ImageURL:     req.ImageURL,
			SourceURL:    req.SourceURL,
			Tags:         req.Tags,
			ColorPrimary: req.ColorPrimary,
			Source:       source,
			Size:         req.Size,
			Material:     req.Material,
			PricePaid:    req.PricePaid,
			RetailPrice:  req.RetailPrice,
			Currency:     req.Currency,
		}
		if item.Name == "" || item.Brand == "" {
			writeError(w, http.StatusBadRequest, "name and brand required")
			return
		}
		if item.Tags == nil {
			item.Tags = []string{}
		}
		if err := d.Wardrobe.Insert(r.Context(), item); err != nil {
			writeError(w, http.StatusInternalServerError, "insert failed")
			return
		}
		writeJSON(w, http.StatusCreated, toWardrobeDTO(*item))
	}
}

func handleMarkWorn(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		id, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		if err := d.Wardrobe.MarkWorn(r.Context(), uid, id); err != nil {
			if errors.Is(err, db.ErrNotFound) {
				writeError(w, http.StatusNotFound, "item not found")
				return
			}
			writeError(w, http.StatusInternalServerError, "update failed")
			return
		}
		item, err := d.Wardrobe.Get(r.Context(), uid, id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "refetch failed")
			return
		}
		writeJSON(w, http.StatusOK, toWardrobeDTO(*item))
	}
}

func handleDeleteWardrobe(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		id, err := uuid.Parse(chi.URLParam(r, "id"))
		if err != nil {
			writeError(w, http.StatusBadRequest, "bad id")
			return
		}
		if err := d.Wardrobe.SoftDelete(r.Context(), uid, id); err != nil {
			if errors.Is(err, db.ErrNotFound) {
				writeError(w, http.StatusNotFound, "item not found")
				return
			}
			writeError(w, http.StatusInternalServerError, "delete failed")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// ----- Outfits -----

type outfitDTO struct {
	ID                uuid.UUID `json:"id"`
	CompositeImageURL *string   `json:"composite_image_url,omitempty"`
	ThumbnailURL      *string   `json:"thumbnail_url,omitempty"`
	Occasion          *string   `json:"occasion,omitempty"`
	Tags              []string  `json:"tags"`
	Visibility        string    `json:"visibility"`
	Source            string    `json:"source"`
	CreatedAt         time.Time `json:"created_at"`
}

type createOutfitReq struct {
	Occasion   *string  `json:"occasion,omitempty"`
	Tags       []string `json:"tags,omitempty"`
	Visibility string   `json:"visibility"`
}

func handleListOutfits(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		outfits, err := d.Outfits.ListByUser(r.Context(), uid, 200)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "list failed")
			return
		}
		out := make([]outfitDTO, 0, len(outfits))
		for _, o := range outfits {
			out = append(out, outfitDTO{
				ID: o.ID, CompositeImageURL: o.CompositeImageURL, ThumbnailURL: o.ThumbnailURL,
				Occasion: o.Occasion, Tags: o.Tags, Visibility: o.Visibility, Source: o.Source,
				CreatedAt: o.CreatedAt,
			})
		}
		writeJSON(w, http.StatusOK, map[string]any{"outfits": out})
	}
}

func handleCreateOutfit(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		uid, _ := auth.UserID(r.Context())
		var req createOutfitReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "invalid body")
			return
		}
		if !validVisibility(req.Visibility) {
			req.Visibility = "friends"
		}
		if req.Tags == nil {
			req.Tags = []string{}
		}
		o := &db.Outfit{
			UserID:     uid,
			Occasion:   req.Occasion,
			Tags:       req.Tags,
			Visibility: req.Visibility,
			Source:     "manual",
		}
		if err := d.Outfits.Insert(r.Context(), o); err != nil {
			writeError(w, http.StatusInternalServerError, "insert failed")
			return
		}
		writeJSON(w, http.StatusCreated, outfitDTO{
			ID: o.ID, Occasion: o.Occasion, Tags: o.Tags,
			Visibility: o.Visibility, Source: o.Source, CreatedAt: o.CreatedAt,
		})
	}
}

// ----- DTOs + helpers -----

type userDTO struct {
	ID          uuid.UUID `json:"id"`
	Email       *string   `json:"email,omitempty"`
	Username    *string   `json:"username,omitempty"`
	DisplayName *string   `json:"display_name,omitempty"`
	AvatarURL   *string   `json:"avatar_url,omitempty"`
	AccountTier string    `json:"account_tier"`
}

func newUserDTO(u *db.User) userDTO {
	return userDTO{
		ID:          u.ID,
		Email:       u.Email,
		Username:    u.Username,
		DisplayName: u.DisplayName,
		AvatarURL:   u.AvatarURL,
		AccountTier: u.AccountTier,
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

func toWardrobeDTO(i db.WardrobeItem) wardrobeItemDTO {
	return wardrobeItemDTO{
		ID:           i.ID,
		Name:         i.Name,
		Brand:        i.Brand,
		Category:     i.Category,
		ImageURL:     i.ImageURL,
		SourceURL:    i.SourceURL,
		Tags:         i.Tags,
		ColorPrimary: i.ColorPrimary,
		Source:       i.Source,
		Size:         i.Size,
		Material:     i.Material,
		PricePaid:    i.PricePaid,
		RetailPrice:  i.RetailPrice,
		Currency:     i.Currency,
		LastWornAt:   i.LastWornAt,
		WearCount:    i.WearCount,
		CreatedAt:    i.CreatedAt,
	}
}

func validCategory(c string) bool {
	switch c {
	case "top", "bottom", "dress", "shoes", "outerwear", "accessory":
		return true
	}
	return false
}

func validVisibility(v string) bool {
	switch v {
	case "private", "friends", "public":
		return true
	}
	return false
}
