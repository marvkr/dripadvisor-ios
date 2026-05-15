package realtime

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type Redis struct {
	Client *redis.Client
}

func Connect(ctx context.Context, addr string) (*Redis, error) {
	c := redis.NewClient(&redis.Options{Addr: addr})
	if err := c.Ping(ctx).Err(); err != nil {
		_ = c.Close()
		return nil, fmt.Errorf("redis ping: %w", err)
	}
	return &Redis{Client: c}, nil
}

// NextSeq atomically assigns the next per-chat sequence via INCR chat:{id}:seq.
// On cold-start (key missing), the caller should pre-seed via SeedSeq from SELECT MAX(seq).
func (r *Redis) NextSeq(ctx context.Context, chatID uuid.UUID) (int64, error) {
	return r.Client.Incr(ctx, chatSeqKey(chatID)).Result()
}

// SeedSeq ensures chat:{id}:seq >= high. Safe to call repeatedly (uses a Lua floor check).
func (r *Redis) SeedSeq(ctx context.Context, chatID uuid.UUID, high int64) error {
	const lua = `local cur = tonumber(redis.call('GET', KEYS[1]) or "0"); if cur < tonumber(ARGV[1]) then redis.call('SET', KEYS[1], ARGV[1]) end; return 1`
	_, err := r.Client.Eval(ctx, lua, []string{chatSeqKey(chatID)}, high).Result()
	return err
}

// PublishUser sends a message to user:{id}. Used for non-chat events (push
// hints, presence) — chat messages now route through PublishChat per the
// 2026-05-12 design revision (groups core → per-chat fan-out).
func (r *Redis) PublishUser(ctx context.Context, userID uuid.UUID, payload []byte) error {
	return r.Client.Publish(ctx, userChannel(userID), payload).Err()
}

// SubscribeUser returns a Redis PubSub subscribed to a single user channel. Caller must Close.
func (r *Redis) SubscribeUser(ctx context.Context, userID uuid.UUID) *redis.PubSub {
	return r.Client.Subscribe(ctx, userChannel(userID))
}

// PublishChat fans out a chat event (new message, edit, delete, reaction)
// to every gateway holding a live socket for any participant of that chat.
// Per locked v1.1 chat design (README "Fan-out & pub/sub").
func (r *Redis) PublishChat(ctx context.Context, chatID uuid.UUID, payload []byte) error {
	return r.Client.Publish(ctx, chatChannel(chatID), payload).Err()
}

// SubscribeChats subscribes to multiple chat channels at once. Caller closes.
func (r *Redis) SubscribeChats(ctx context.Context, chatIDs ...uuid.UUID) *redis.PubSub {
	channels := make([]string, len(chatIDs))
	for i, id := range chatIDs {
		channels[i] = chatChannel(id)
	}
	return r.Client.Subscribe(ctx, channels...)
}

// TypingHeartbeat sets a short-TTL flag for a user typing in a chat.
func (r *Redis) TypingHeartbeat(ctx context.Context, chatID, userID uuid.UUID, ttl time.Duration) error {
	key := fmt.Sprintf("typing:%s:%s", chatID, userID)
	return r.Client.Set(ctx, key, "1", ttl).Err()
}

func (r *Redis) Close() error { return r.Client.Close() }

func chatSeqKey(chatID uuid.UUID) string  { return "chat:" + chatID.String() + ":seq" }
func userChannel(userID uuid.UUID) string { return "user:" + userID.String() }
func chatChannel(chatID uuid.UUID) string { return "chat:" + chatID.String() }
