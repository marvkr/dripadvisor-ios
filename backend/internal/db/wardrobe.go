package db

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type WardrobeItem struct {
	ID           uuid.UUID
	UserID       uuid.UUID
	Name         string
	Brand        string
	Category     string
	ImageURL     *string
	SourceURL    *string
	Tags         []string
	ColorPrimary *string
	Source       string // 'owned' or 'wishlist'
	Size         *string
	Material     *string
	PricePaid    *float64
	RetailPrice  *float64
	Currency     *string // ISO 4217
	LastWornAt   *time.Time
	WearCount    int
	CreatedAt    time.Time
}

type WardrobeRepo struct {
	pool *pgxpool.Pool
}

func NewWardrobeRepo(pool *pgxpool.Pool) *WardrobeRepo { return &WardrobeRepo{pool: pool} }

func (r *WardrobeRepo) Insert(ctx context.Context, w *WardrobeItem) error {
	if w.Source == "" {
		w.Source = "owned"
	}
	const q = `
INSERT INTO wardrobe_items (
    user_id, name, brand, category, image_url, source_url, tags, color_primary,
    source, size, material, price_paid, retail_price, currency, last_worn_at, wear_count
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
RETURNING id, created_at`
	return r.pool.QueryRow(ctx, q,
		w.UserID, w.Name, w.Brand, w.Category, w.ImageURL, w.SourceURL, w.Tags, w.ColorPrimary,
		w.Source, w.Size, w.Material, w.PricePaid, w.RetailPrice, w.Currency, w.LastWornAt, w.WearCount,
	).Scan(&w.ID, &w.CreatedAt)
}

func (r *WardrobeRepo) ListByUser(ctx context.Context, userID uuid.UUID, limit int) ([]WardrobeItem, error) {
	const q = `
SELECT id, user_id, name, brand, category, image_url, source_url, tags, color_primary,
       source, size, material, price_paid, retail_price, currency, last_worn_at, wear_count, created_at
FROM wardrobe_items
WHERE user_id = $1 AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT $2`
	rows, err := r.pool.Query(ctx, q, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]WardrobeItem, 0, limit)
	for rows.Next() {
		w, err := scanWardrobe(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

func (r *WardrobeRepo) SoftDelete(ctx context.Context, userID, itemID uuid.UUID) error {
	const q = `UPDATE wardrobe_items SET deleted_at = now() WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`
	ct, err := r.pool.Exec(ctx, q, itemID, userID)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *WardrobeRepo) Get(ctx context.Context, userID, itemID uuid.UUID) (*WardrobeItem, error) {
	const q = `
SELECT id, user_id, name, brand, category, image_url, source_url, tags, color_primary,
       source, size, material, price_paid, retail_price, currency, last_worn_at, wear_count, created_at
FROM wardrobe_items
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`
	row := r.pool.QueryRow(ctx, q, itemID, userID)
	w, err := scanWardrobe(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &w, nil
}

// MarkWorn updates last_worn_at + bumps wear_count. Used by "Mark as worn" CTA
// on owned items.
func (r *WardrobeRepo) MarkWorn(ctx context.Context, userID, itemID uuid.UUID) error {
	const q = `
UPDATE wardrobe_items
SET last_worn_at = now(), wear_count = wear_count + 1, updated_at = now()
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`
	ct, err := r.pool.Exec(ctx, q, itemID, userID)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanWardrobe(s rowScanner) (WardrobeItem, error) {
	var w WardrobeItem
	err := s.Scan(
		&w.ID, &w.UserID, &w.Name, &w.Brand, &w.Category, &w.ImageURL, &w.SourceURL,
		&w.Tags, &w.ColorPrimary, &w.Source, &w.Size, &w.Material, &w.PricePaid,
		&w.RetailPrice, &w.Currency, &w.LastWornAt, &w.WearCount, &w.CreatedAt,
	)
	return w, err
}
