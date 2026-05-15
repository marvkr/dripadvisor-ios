package db

import (
	"context"

	"github.com/google/uuid"
)

// Inbox is the per-user-per-chat durability backstop for at-most-once Redis
// pub/sub. When a message lands, we insert/update an inbox row for every
// participant; on reconnect, the client asks for everything > last_read_seq
// in each chat and we serve from messages table directly. Inbox stores
// pinned/muted state + unread_count for the chat list.

// BumpInboxOnNewMessage recomputes inbox state for every participant when a
// message lands. Idempotent on (user_id, chat_id) PK.
func (r *ChatRepo) BumpInboxOnNewMessage(ctx context.Context, chatID uuid.UUID, _seq int64) error {
	const q = `
INSERT INTO inbox (user_id, chat_id, last_read_seq, unread_count, pinned, updated_at)
SELECT p.user_id, $1, p.last_read_seq, 0, FALSE, now()
FROM chat_participants p
WHERE p.chat_id = $1 AND p.user_id IS NOT NULL
ON CONFLICT (user_id, chat_id) DO UPDATE
SET unread_count = inbox.unread_count + 1,
    updated_at   = now()`
	_, err := r.pool.Exec(ctx, q, chatID)
	return err
}

// ResetUnread is called when a user marks a chat read (last_read_seq advances).
func (r *ChatRepo) ResetUnread(ctx context.Context, userID, chatID uuid.UUID) error {
	const q = `
UPDATE inbox SET unread_count = 0, updated_at = now()
WHERE user_id = $1 AND chat_id = $2`
	_, err := r.pool.Exec(ctx, q, userID, chatID)
	return err
}
