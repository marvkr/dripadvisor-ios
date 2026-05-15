package workers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/riverqueue/river"
	"github.com/riverqueue/river/riverdriver/riverpgxv5"
	"github.com/riverqueue/river/rivermigrate"

	"github.com/dripadvisor/backend/internal/db"
	"github.com/dripadvisor/backend/internal/gemini"
	"github.com/dripadvisor/backend/internal/realtime"
)

const (
	QueueCritical = "critical"
	QueueDefault  = "default"
	QueueLow      = "low"
)

// Job args

type ExtractGarmentArgs struct {
	IngestionID string `json:"ingestion_id"`
}

func (ExtractGarmentArgs) Kind() string { return "extract_garment" }

type IngestBookmarkArgs struct {
	UserID    string `json:"user_id"`
	SourceURL string `json:"source_url"`
	Hash      string `json:"hash"`
}

func (IngestBookmarkArgs) Kind() string { return "ingest_bookmark" }

type ComposeOutfitArgs struct {
	UserID     string   `json:"user_id"`
	OutfitID   string   `json:"outfit_id"`
	ItemIDs    []string `json:"item_ids"`
	Occasion   string   `json:"occasion"`
	BodyPhotoK string   `json:"body_photo_key"`
}

func (ComposeOutfitArgs) Kind() string { return "compose_outfit" }

type StylistReplyArgs struct {
	ChatID  string `json:"chat_id"`
	UserID  string `json:"user_id"`
	Prompt  string `json:"prompt"`
	IdemKey string `json:"idempotency_key"`
}

func (StylistReplyArgs) Kind() string { return "stylist_reply" }

type PushSendArgs struct {
	UserID string            `json:"user_id"`
	Title  string            `json:"title"`
	Body   string            `json:"body"`
	Data   map[string]string `json:"data,omitempty"`
}

func (PushSendArgs) Kind() string { return "push_send" }

type AgedMessagePurgeArgs struct{}

func (AgedMessagePurgeArgs) Kind() string { return "aged_message_purge" }

// Workers (bodies filled in during later tasks; logging-only for now)

type ExtractGarmentWorker struct {
	river.WorkerDefaults[ExtractGarmentArgs]
}

func (w *ExtractGarmentWorker) Work(ctx context.Context, job *river.Job[ExtractGarmentArgs]) error {
	slog.InfoContext(ctx, "extract_garment", "ingestion_id", job.Args.IngestionID)
	return nil
}

type IngestBookmarkWorker struct {
	river.WorkerDefaults[IngestBookmarkArgs]
}

func (w *IngestBookmarkWorker) Work(ctx context.Context, job *river.Job[IngestBookmarkArgs]) error {
	slog.InfoContext(ctx, "ingest_bookmark", "user_id", job.Args.UserID, "url", job.Args.SourceURL)
	return nil
}

type ComposeOutfitWorker struct {
	river.WorkerDefaults[ComposeOutfitArgs]
	Gemini ComposeOutfitGemini // injected; nil in tests / no-op mode
}

// ComposeOutfitGemini abstracts the Gemini call so the worker can be tested
// without hitting the real API.
type ComposeOutfitGemini interface {
	ComposeOutfit(ctx context.Context, job ComposeOutfitArgs) ([]byte, error)
}

func (w *ComposeOutfitWorker) Work(ctx context.Context, job *river.Job[ComposeOutfitArgs]) error {
	slog.InfoContext(ctx, "compose_outfit", "outfit_id", job.Args.OutfitID)
	if w.Gemini == nil {
		slog.WarnContext(ctx, "compose_outfit skipped: Gemini client not configured")
		return nil
	}
	if _, err := w.Gemini.ComposeOutfit(ctx, job.Args); err != nil {
		return fmt.Errorf("compose_outfit: %w", err)
	}
	return nil
}

// Stylist agent UUID seeded in migration 0001 (`Drip Stylist`, persona
// drip_stylist_v1). Worker uses this when writing reply messages.
const StylistAgentID = "11111111-1111-1111-1111-111111111111"

const stylistSystemPrompt = `You are Drip Stylist, a warm, opinionated personal stylist embedded in a private group chat.
- Always read the user's wardrobe by calling lookup_wardrobe before recommending. Don't invent items.
- Be concise (2-4 sentences max). Suggest one outfit at a time.
- Format proposals as "Try the {top} with the {bottom} and {shoes}." Reference the items by their name.
- Match the occasion the user mentions (rooftop, work, brunch, etc.).
- Never reveal that you're an LLM. Skip pleasantries.`

type StylistReplyWorker struct {
	river.WorkerDefaults[StylistReplyArgs]
	Chats    *db.ChatRepo
	Wardrobe *db.WardrobeRepo
	Stylist  *gemini.Stylist
	Realtime *realtime.Redis
}

func (w *StylistReplyWorker) Work(ctx context.Context, job *river.Job[StylistReplyArgs]) error {
	if w.Chats == nil || w.Stylist == nil {
		slog.WarnContext(ctx, "stylist_reply skipped: deps not wired")
		return nil
	}
	chatID, err := uuid.Parse(job.Args.ChatID)
	if err != nil {
		return fmt.Errorf("bad chat_id: %w", err)
	}
	userID, err := uuid.Parse(job.Args.UserID)
	if err != nil {
		return fmt.Errorf("bad user_id: %w", err)
	}

	// Pull recent context (last 20 messages). Drop deleted ones.
	msgs, err := w.Chats.ListMessages(ctx, chatID, 0, 200)
	if err != nil {
		return fmt.Errorf("list ctx: %w", err)
	}
	if len(msgs) > 20 {
		msgs = msgs[len(msgs)-20:]
	}
	history := make([]gemini.ChatMessage, 0, len(msgs))
	for _, m := range msgs {
		if m.DeletedAt != nil || m.Body == nil {
			continue
		}
		role := "user"
		if m.SenderAgentID != nil {
			role = "assistant"
		}
		history = append(history, gemini.ChatMessage{Role: role, Content: *m.Body})
	}

	lookup := func(ctx context.Context, q gemini.WardrobeQuery) ([]map[string]any, error) {
		// PR3 ships a coarse lookup: list everything for the user, filter
		// in-process. Faster path (indexed `category`/`source`/`color_primary`
		// queries) lands when wardrobe-stylist read patterns are tuned.
		items, err := w.Wardrobe.ListByUser(ctx, userID, 200)
		if err != nil {
			return nil, err
		}
		out := make([]map[string]any, 0, len(items))
		for _, it := range items {
			if q.Category != nil && it.Category != *q.Category {
				continue
			}
			if q.Source != nil && it.Source != *q.Source {
				continue
			}
			if q.Color != nil && it.ColorPrimary != nil &&
				!strings.EqualFold(*it.ColorPrimary, *q.Color) {
				continue
			}
			out = append(out, map[string]any{
				"id":       it.ID,
				"name":     it.Name,
				"brand":    it.Brand,
				"category": it.Category,
				"color":    it.ColorPrimary,
				"source":   it.Source,
			})
			if q.Limit != nil && len(out) >= *q.Limit {
				break
			}
		}
		return out, nil
	}

	body, err := w.Stylist.Reply(ctx, stylistSystemPrompt, history, lookup)
	if err != nil {
		return fmt.Errorf("stylist reply: %w", err)
	}
	if body == "" {
		return errors.New("stylist returned empty body")
	}

	agentID := uuid.MustParse(StylistAgentID)
	reply := &db.Message{
		ChatID:        chatID,
		SenderAgentID: &agentID,
		Body:          &body,
	}

	if w.Realtime != nil {
		seq, err := w.Realtime.NextSeq(ctx, chatID)
		if err != nil {
			return fmt.Errorf("seq: %w", err)
		}
		reply.Seq = seq
		if err := w.Chats.InsertMessage(ctx, reply); err != nil {
			return fmt.Errorf("insert reply: %w", err)
		}
	} else {
		if err := w.Chats.SendMessage(ctx, reply); err != nil {
			return fmt.Errorf("send reply: %w", err)
		}
	}

	if err := w.Chats.BumpInboxOnNewMessage(ctx, chatID, reply.Seq); err != nil {
		slog.WarnContext(ctx, "inbox bump failed", "err", err.Error())
	}

	if w.Realtime != nil {
		payload, _ := json.Marshal(map[string]any{
			"type":    "message.new",
			"message": reply,
		})
		_ = w.Realtime.PublishChat(ctx, chatID, payload)
	}

	slog.InfoContext(ctx, "stylist_reply sent",
		"chat_id", chatID.String(), "seq", reply.Seq, "len", len(body))
	return nil
}

type PushSendWorker struct {
	river.WorkerDefaults[PushSendArgs]
}

func (w *PushSendWorker) Work(ctx context.Context, job *river.Job[PushSendArgs]) error {
	slog.InfoContext(ctx, "push_send", "user_id", job.Args.UserID, "title", job.Args.Title)
	return nil
}

type AgedMessagePurgeWorker struct {
	river.WorkerDefaults[AgedMessagePurgeArgs]
}

func (w *AgedMessagePurgeWorker) Work(ctx context.Context, _ *river.Job[AgedMessagePurgeArgs]) error {
	slog.InfoContext(ctx, "aged_message_purge")
	return nil
}

// Migrate applies the River schema (river_queue, river_job, etc.) idempotently.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	m, err := rivermigrate.New(riverpgxv5.New(pool), nil)
	if err != nil {
		return err
	}
	_, err = m.Migrate(ctx, rivermigrate.DirectionUp, nil)
	return err
}

// Deps bundles everything workers need so main.go can wire once.
type Deps struct {
	Chats    *db.ChatRepo
	Wardrobe *db.WardrobeRepo
	Stylist  *gemini.Stylist
	Realtime *realtime.Redis
}

// NewClient wires River with the default worker set + 3 queues.
func NewClient(pool *pgxpool.Pool, d Deps) (*river.Client[pgx.Tx], error) {
	ws := river.NewWorkers()
	river.AddWorker(ws, &ExtractGarmentWorker{})
	river.AddWorker(ws, &IngestBookmarkWorker{})
	river.AddWorker(ws, &ComposeOutfitWorker{})
	river.AddWorker(ws, &StylistReplyWorker{
		Chats:    d.Chats,
		Wardrobe: d.Wardrobe,
		Stylist:  d.Stylist,
		Realtime: d.Realtime,
	})
	river.AddWorker(ws, &PushSendWorker{})
	river.AddWorker(ws, &AgedMessagePurgeWorker{})

	return river.NewClient(riverpgxv5.New(pool), &river.Config{
		Queues: map[string]river.QueueConfig{
			QueueCritical: {MaxWorkers: 40},
			QueueDefault:  {MaxWorkers: 50},
			QueueLow:      {MaxWorkers: 5},
		},
		Workers: ws,
	})
}
