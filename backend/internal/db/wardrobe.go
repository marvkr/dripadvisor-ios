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
	CreatedAt    time.Time
}

type WardrobeRepo struct {
	pool *pgxpool.Pool
}

func NewWardrobeRepo(pool *pgxpool.Pool) *WardrobeRepo { return &WardrobeRepo{pool: pool} }

func (r *WardrobeRepo) Insert(ctx context.Context, w *WardrobeItem) error {
	const q = `
INSERT INTO wardrobe_items (user_id, name, brand, category, image_url, source_url, tags, color_primary)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id, created_at`
	return r.pool.QueryRow(ctx, q,
		w.UserID, w.Name, w.Brand, w.Category, w.ImageURL, w.SourceURL, w.Tags, w.ColorPrimary,
	).Scan(&w.ID, &w.CreatedAt)
}

func (r *WardrobeRepo) ListByUser(ctx context.Context, userID uuid.UUID, limit int) ([]WardrobeItem, error) {
	const q = `
SELECT id, user_id, name, brand, category, image_url, source_url, tags, color_primary, created_at
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
		var w WardrobeItem
		if err := rows.Scan(&w.ID, &w.UserID, &w.Name, &w.Brand, &w.Category,
			&w.ImageURL, &w.SourceURL, &w.Tags, &w.ColorPrimary, &w.CreatedAt); err != nil {
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
SELECT id, user_id, name, brand, category, image_url, source_url, tags, color_primary, created_at
FROM wardrobe_items
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`
	var w WardrobeItem
	err := r.pool.QueryRow(ctx, q, itemID, userID).Scan(
		&w.ID, &w.UserID, &w.Name, &w.Brand, &w.Category,
		&w.ImageURL, &w.SourceURL, &w.Tags, &w.ColorPrimary, &w.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &w, err
}
