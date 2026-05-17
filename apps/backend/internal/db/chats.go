package db

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Chat is a v1.1 conversation. Type 'direct' = 1:1 (user + user OR user +
// agent), 'group' = ≤8 participants.
type Chat struct {
	ID                   uuid.UUID
	Type                 string // 'direct' | 'group'
	Name                 *string
	IconURL              *string
	CreatedBy            *uuid.UUID
	LastMessageAt        *time.Time
	LastMessagePreview   *string
	CreatedAt            time.Time
	UpdatedAt            time.Time
}

type ChatParticipant struct {
	ChatID               uuid.UUID
	UserID               *uuid.UUID
	AgentID              *uuid.UUID
	Role                 string
	JoinedAt             time.Time
	LastReadSeq          int64
	NotificationsEnabled bool
	SharesWardrobe       bool
}

type Message struct {
	ID             uuid.UUID
	ChatID         uuid.UUID
	SenderUserID   *uuid.UUID
	SenderAgentID  *uuid.UUID
	Seq            int64
	Body           *string
	AttachmentType *string // 'outfit' | 'item' | 'image' | 'link'
	AttachmentID   *uuid.UUID
	ReplyToID      *uuid.UUID
	CreatedAt      time.Time
	EditedAt       *time.Time
	DeletedAt      *time.Time
}

type Reaction struct {
	MessageID uuid.UUID
	UserID    uuid.UUID
	Emoji     string
	CreatedAt time.Time
}

type ChatRepo struct {
	pool *pgxpool.Pool
}

func NewChatRepo(pool *pgxpool.Pool) *ChatRepo { return &ChatRepo{pool: pool} }

// CreateChat inserts a new chat and adds initial participants atomically.
// `creator` is the admin. `participants` is the user IDs (creator excluded —
// added automatically as admin). `agentIDs` adds AI agents to the chat.
func (r *ChatRepo) CreateChat(
	ctx context.Context,
	chatType string,
	name *string,
	creator uuid.UUID,
	participants []uuid.UUID,
	agentIDs []uuid.UUID,
) (*Chat, error) {
	if chatType != "direct" && chatType != "group" {
		return nil, errors.New("invalid chat type")
	}
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	c := &Chat{Type: chatType, Name: name, CreatedBy: &creator}
	err = tx.QueryRow(ctx, `
INSERT INTO chats (type, name, created_by)
VALUES ($1, $2, $3)
RETURNING id, created_at, updated_at`, chatType, name, creator).Scan(&c.ID, &c.CreatedAt, &c.UpdatedAt)
	if err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx, `
INSERT INTO chat_participants (chat_id, user_id, role)
VALUES ($1, $2, 'admin')`, c.ID, creator); err != nil {
		return nil, err
	}

	for _, uid := range participants {
		if uid == creator {
			continue
		}
		if _, err := tx.Exec(ctx, `
INSERT INTO chat_participants (chat_id, user_id, role) VALUES ($1, $2, 'member')`,
			c.ID, uid); err != nil {
			return nil, err
		}
	}
	for _, aid := range agentIDs {
		if _, err := tx.Exec(ctx, `
INSERT INTO chat_participants (chat_id, agent_id, role) VALUES ($1, $2, 'member')`,
			c.ID, aid); err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return c, nil
}

// ListChatsForUser returns chats the user is a participant in, sorted by
// last_message_at desc.
func (r *ChatRepo) ListChatsForUser(ctx context.Context, userID uuid.UUID, limit int) ([]Chat, error) {
	const q = `
SELECT c.id, c.type, c.name, c.icon_url, c.created_by, c.last_message_at,
       c.last_message_preview, c.created_at, c.updated_at
FROM chats c
JOIN chat_participants p ON p.chat_id = c.id
WHERE p.user_id = $1
ORDER BY c.last_message_at DESC NULLS LAST, c.created_at DESC
LIMIT $2`
	rows, err := r.pool.Query(ctx, q, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Chat{}
	for rows.Next() {
		var c Chat
		if err := rows.Scan(&c.ID, &c.Type, &c.Name, &c.IconURL, &c.CreatedBy,
			&c.LastMessageAt, &c.LastMessagePreview, &c.CreatedAt, &c.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (r *ChatRepo) GetChat(ctx context.Context, chatID uuid.UUID) (*Chat, error) {
	const q = `
SELECT id, type, name, icon_url, created_by, last_message_at,
       last_message_preview, created_at, updated_at
FROM chats WHERE id = $1`
	var c Chat
	err := r.pool.QueryRow(ctx, q, chatID).Scan(&c.ID, &c.Type, &c.Name, &c.IconURL,
		&c.CreatedBy, &c.LastMessageAt, &c.LastMessagePreview, &c.CreatedAt, &c.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &c, err
}

func (r *ChatRepo) ListParticipants(ctx context.Context, chatID uuid.UUID) ([]ChatParticipant, error) {
	const q = `
SELECT chat_id, user_id, agent_id, role, joined_at, last_read_seq,
       notifications_enabled, shares_wardrobe
FROM chat_participants
WHERE chat_id = $1
ORDER BY joined_at ASC`
	rows, err := r.pool.Query(ctx, q, chatID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ChatParticipant{}
	for rows.Next() {
		var p ChatParticipant
		if err := rows.Scan(&p.ChatID, &p.UserID, &p.AgentID, &p.Role, &p.JoinedAt,
			&p.LastReadSeq, &p.NotificationsEnabled, &p.SharesWardrobe); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (r *ChatRepo) IsParticipant(ctx context.Context, chatID, userID uuid.UUID) (bool, string, error) {
	var role string
	err := r.pool.QueryRow(ctx,
		`SELECT role FROM chat_participants WHERE chat_id = $1 AND user_id = $2`,
		chatID, userID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, "", nil
	}
	if err != nil {
		return false, "", err
	}
	return true, role, nil
}

// FindDirectChatWithAgent returns the existing direct chat that has both the
// user and the given agent as participants, or ErrNotFound when absent.
func (r *ChatRepo) FindDirectChatWithAgent(ctx context.Context, userID, agentID uuid.UUID) (*Chat, error) {
	const q = `
SELECT c.id, c.type, c.name, c.icon_url, c.created_by, c.last_message_at,
       c.last_message_preview, c.created_at, c.updated_at
FROM chats c
JOIN chat_participants pu ON pu.chat_id = c.id AND pu.user_id  = $1
JOIN chat_participants pa ON pa.chat_id = c.id AND pa.agent_id = $2
WHERE c.type = 'direct'
LIMIT 1`
	var c Chat
	err := r.pool.QueryRow(ctx, q, userID, agentID).Scan(&c.ID, &c.Type, &c.Name,
		&c.IconURL, &c.CreatedBy, &c.LastMessageAt, &c.LastMessagePreview,
		&c.CreatedAt, &c.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &c, err
}

func (r *ChatRepo) AddParticipant(ctx context.Context, chatID, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO chat_participants (chat_id, user_id, role) VALUES ($1, $2, 'member')`,
		chatID, userID)
	return err
}

func (r *ChatRepo) RemoveParticipant(ctx context.Context, chatID, userID uuid.UUID) error {
	ct, err := r.pool.Exec(ctx,
		`DELETE FROM chat_participants WHERE chat_id = $1 AND user_id = $2`,
		chatID, userID)
	if err != nil {
		return err
	}
	if ct.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// InsertMessage writes a row at the supplied seq + updates the chat's last
// preview. Caller assigns seq beforehand (typically via redis.INCR per the
// locked v1.1 design). Use SendMessage if you'd rather have the repo handle
// seq via Postgres advisory lock (slower fallback).
func (r *ChatRepo) InsertMessage(ctx context.Context, m *Message) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	const ins = `
INSERT INTO messages (chat_id, sender_user_id, sender_agent_id, seq, body,
                      attachment_type, attachment_id, reply_to_id)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING id, created_at`
	if err := tx.QueryRow(ctx, ins,
		m.ChatID, m.SenderUserID, m.SenderAgentID, m.Seq, m.Body,
		m.AttachmentType, m.AttachmentID, m.ReplyToID,
	).Scan(&m.ID, &m.CreatedAt); err != nil {
		return err
	}

	preview := ""
	if m.Body != nil {
		if len(*m.Body) > 200 {
			preview = (*m.Body)[:200]
		} else {
			preview = *m.Body
		}
	}
	if _, err := tx.Exec(ctx, `
UPDATE chats
SET last_message_at = $2, last_message_preview = $3, updated_at = now()
WHERE id = $1`, m.ChatID, m.CreatedAt, preview); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// SendMessage assigns seq via Postgres advisory lock + COALESCE(MAX,0)+1.
// Kept as a fallback when Redis is unavailable. Production path uses
// realtime.NextSeq + InsertMessage directly.
func (r *ChatRepo) SendMessage(ctx context.Context, m *Message) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx,
		`SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))`, m.ChatID); err != nil {
		return err
	}
	if err := tx.QueryRow(ctx,
		`SELECT COALESCE(MAX(seq), 0) + 1 FROM messages WHERE chat_id = $1`,
		m.ChatID).Scan(&m.Seq); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	return r.InsertMessage(ctx, m)
}

// ChatIDsForUser returns every chat the user participates in. Used by the
// gateway on connect to subscribe Redis chat:{id} channels.
func (r *ChatRepo) ChatIDsForUser(ctx context.Context, userID uuid.UUID) ([]uuid.UUID, error) {
	const q = `
SELECT chat_id FROM chat_participants
WHERE user_id = $1
ORDER BY chat_id`
	rows, err := r.pool.Query(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []uuid.UUID{}
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// ListMessages returns messages newer than `afterSeq` (or all if 0), capped.
func (r *ChatRepo) ListMessages(ctx context.Context, chatID uuid.UUID, afterSeq int64, limit int) ([]Message, error) {
	const q = `
SELECT id, chat_id, sender_user_id, sender_agent_id, seq, body,
       attachment_type, attachment_id, reply_to_id, created_at, edited_at, deleted_at
FROM messages
WHERE chat_id = $1 AND seq > $2
ORDER BY seq ASC
LIMIT $3`
	rows, err := r.pool.Query(ctx, q, chatID, afterSeq, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.ChatID, &m.SenderUserID, &m.SenderAgentID,
			&m.Seq, &m.Body, &m.AttachmentType, &m.AttachmentID, &m.ReplyToID,
			&m.CreatedAt, &m.EditedAt, &m.DeletedAt); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// SetReadCursor advances the user's last_read_seq for a chat (idempotent;
// only moves forward).
func (r *ChatRepo) SetReadCursor(ctx context.Context, chatID, userID uuid.UUID, seq int64) error {
	_, err := r.pool.Exec(ctx, `
UPDATE chat_participants
SET last_read_seq = GREATEST(last_read_seq, $3)
WHERE chat_id = $1 AND user_id = $2`, chatID, userID, seq)
	return err
}

func (r *ChatRepo) AddReaction(ctx context.Context, msgID, userID uuid.UUID, emoji string) error {
	_, err := r.pool.Exec(ctx, `
INSERT INTO message_reactions (message_id, user_id, emoji)
VALUES ($1, $2, $3)
ON CONFLICT DO NOTHING`, msgID, userID, emoji)
	return err
}

func (r *ChatRepo) RemoveReaction(ctx context.Context, msgID, userID uuid.UUID, emoji string) error {
	_, err := r.pool.Exec(ctx, `
DELETE FROM message_reactions WHERE message_id = $1 AND user_id = $2 AND emoji = $3`,
		msgID, userID, emoji)
	return err
}

func (r *ChatRepo) ListReactions(ctx context.Context, msgIDs []uuid.UUID) (map[uuid.UUID][]Reaction, error) {
	out := map[uuid.UUID][]Reaction{}
	if len(msgIDs) == 0 {
		return out, nil
	}
	rows, err := r.pool.Query(ctx, `
SELECT message_id, user_id, emoji, created_at
FROM message_reactions
WHERE message_id = ANY($1)
ORDER BY created_at ASC`, msgIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var r Reaction
		if err := rows.Scan(&r.MessageID, &r.UserID, &r.Emoji, &r.CreatedAt); err != nil {
			return nil, err
		}
		out[r.MessageID] = append(out[r.MessageID], r)
	}
	return out, rows.Err()
}
