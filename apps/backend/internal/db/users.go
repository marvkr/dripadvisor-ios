package db

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("not found")

type User struct {
	ID           uuid.UUID
	AppleSub     *string
	Email        *string
	Username     *string
	DisplayName  *string
	AvatarURL    *string
	AccountTier  string
	ProExpiresAt *time.Time
	OnboardedAt  *time.Time
	CreatedAt    time.Time
}

type UserRepo struct {
	pool *pgxpool.Pool
}

func NewUserRepo(pool *pgxpool.Pool) *UserRepo { return &UserRepo{pool: pool} }

// UpsertByAppleSub inserts or returns an existing user identified by Apple sub.
func (r *UserRepo) UpsertByAppleSub(ctx context.Context, appleSub, email string) (*User, error) {
	const q = `
INSERT INTO users (apple_sub, email, account_tier)
VALUES ($1, NULLIF($2, ''), 'free')
ON CONFLICT (apple_sub) DO UPDATE SET updated_at = now()
RETURNING id, apple_sub, email, username, display_name, avatar_url, account_tier, pro_expires_at, onboarded_at, created_at`

	row := r.pool.QueryRow(ctx, q, appleSub, email)
	return scanUser(row)
}

func (r *UserRepo) SetAvatarURL(ctx context.Context, id uuid.UUID, url string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE users SET avatar_url = $2, updated_at = now() WHERE id = $1`,
		id, url)
	return err
}

func (r *UserRepo) GetByID(ctx context.Context, id uuid.UUID) (*User, error) {
	const q = `
SELECT id, apple_sub, email, username, display_name, avatar_url, account_tier, pro_expires_at, onboarded_at, created_at
FROM users WHERE id = $1 AND deleted_at IS NULL`
	row := r.pool.QueryRow(ctx, q, id)
	u, err := scanUser(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return u, err
}

func scanUser(row pgx.Row) (*User, error) {
	var u User
	err := row.Scan(
		&u.ID,
		&u.AppleSub,
		&u.Email,
		&u.Username,
		&u.DisplayName,
		&u.AvatarURL,
		&u.AccountTier,
		&u.ProExpiresAt,
		&u.OnboardedAt,
		&u.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &u, nil
}
