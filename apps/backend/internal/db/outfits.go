package db

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Outfit struct {
	ID                 uuid.UUID
	UserID             uuid.UUID
	CompositeImageURL  *string
	ThumbnailURL       *string
	Occasion           *string
	Tags               []string
	Visibility         string
	Source             string
	RemixOf            *uuid.UUID
	CreatedAt          time.Time
}

type OutfitRepo struct {
	pool *pgxpool.Pool
}

func NewOutfitRepo(pool *pgxpool.Pool) *OutfitRepo { return &OutfitRepo{pool: pool} }

func (r *OutfitRepo) Insert(ctx context.Context, o *Outfit) error {
	const q = `
INSERT INTO outfits (user_id, composite_image_url, thumbnail_url, occasion, tags, visibility, source, remix_of)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id, created_at`
	return r.pool.QueryRow(ctx, q,
		o.UserID, o.CompositeImageURL, o.ThumbnailURL, o.Occasion, o.Tags, o.Visibility, o.Source, o.RemixOf,
	).Scan(&o.ID, &o.CreatedAt)
}

func (r *OutfitRepo) ListByUser(ctx context.Context, userID uuid.UUID, limit int) ([]Outfit, error) {
	const q = `
SELECT id, user_id, composite_image_url, thumbnail_url, occasion, tags, visibility, source, remix_of, created_at
FROM outfits
WHERE user_id = $1 AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT $2`
	rows, err := r.pool.Query(ctx, q, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Outfit, 0, limit)
	for rows.Next() {
		var o Outfit
		if err := rows.Scan(&o.ID, &o.UserID, &o.CompositeImageURL, &o.ThumbnailURL,
			&o.Occasion, &o.Tags, &o.Visibility, &o.Source, &o.RemixOf, &o.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, o)
	}
	return out, rows.Err()
}
