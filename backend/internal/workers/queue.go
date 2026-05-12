package workers

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/riverqueue/river"
	"github.com/riverqueue/river/riverdriver/riverpgxv5"
	"github.com/riverqueue/river/rivermigrate"
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

type StylistReplyWorker struct {
	river.WorkerDefaults[StylistReplyArgs]
}

func (w *StylistReplyWorker) Work(ctx context.Context, job *river.Job[StylistReplyArgs]) error {
	slog.InfoContext(ctx, "stylist_reply", "chat_id", job.Args.ChatID)
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

// NewClient wires River with the default worker set + 3 queues.
func NewClient(pool *pgxpool.Pool) (*river.Client[pgx.Tx], error) {
	ws := river.NewWorkers()
	river.AddWorker(ws, &ExtractGarmentWorker{})
	river.AddWorker(ws, &IngestBookmarkWorker{})
	river.AddWorker(ws, &ComposeOutfitWorker{})
	river.AddWorker(ws, &StylistReplyWorker{})
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
