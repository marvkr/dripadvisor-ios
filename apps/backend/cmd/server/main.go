package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/dripadvisor/backend/internal/auth"
	"github.com/dripadvisor/backend/internal/config"
	"github.com/dripadvisor/backend/internal/db"
	"github.com/dripadvisor/backend/internal/gemini"
	"github.com/dripadvisor/backend/internal/httpapi"
	"github.com/dripadvisor/backend/internal/realtime"
	"github.com/dripadvisor/backend/internal/storage"
	"github.com/dripadvisor/backend/internal/workers"
)

func main() {
	migrateOnly := flag.Bool("migrate", false, "run migrations and exit")
	flag.Parse()

	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})))

	cfg, err := config.Load()
	if err != nil {
		slog.Error("config", "err", err.Error())
		os.Exit(1)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("db connect", "err", err.Error())
		os.Exit(1)
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		slog.Error("migrate", "err", err.Error())
		os.Exit(1)
	}
	if err := workers.Migrate(ctx, pool); err != nil {
		slog.Error("river migrate", "err", err.Error())
		os.Exit(1)
	}
	if *migrateOnly {
		slog.Info("migrations applied; exiting")
		return
	}

	rdb, err := realtime.Connect(ctx, cfg.RedisAddr)
	if err != nil {
		slog.Error("redis", "err", err.Error())
		os.Exit(1)
	}
	defer func() { _ = rdb.Close() }()

	store, err := storage.New(ctx, storage.Options{
		Endpoint:     cfg.S3Endpoint,
		AccessKey:    cfg.S3AccessKey,
		SecretKey:    cfg.S3SecretKey,
		Bucket:       cfg.S3Bucket,
		Region:       cfg.S3Region,
		UsePathStyle: cfg.S3UsePathStyle,
	})
	if err != nil {
		slog.Error("storage", "err", err.Error())
		os.Exit(1)
	}
	if cfg.Env == "dev" {
		if err := store.EnsureBucket(ctx); err != nil {
			slog.Warn("ensure bucket", "err", err.Error())
		}
	}

	riverClient, err := workers.NewClient(pool)
	if err != nil {
		slog.Error("river", "err", err.Error())
		os.Exit(1)
	}
	if err := riverClient.Start(ctx); err != nil {
		slog.Error("river start", "err", err.Error())
		os.Exit(1)
	}

	var geminiClient *gemini.Client
	if cfg.GeminiAPIKey != "" {
		geminiClient, err = gemini.New(ctx, cfg.GeminiAPIKey)
		if err != nil {
			slog.Warn("gemini init failed; /v1/tryon disabled", "err", err.Error())
			geminiClient = nil
		}
	} else {
		slog.Warn("GEMINI_API_KEY not set; /v1/tryon disabled")
	}

	chats := db.NewChatRepo(pool)
	gateway := realtime.NewGateway(rdb, chats)

	deps := &httpapi.Deps{
		Users:    db.NewUserRepo(pool),
		Wardrobe: db.NewWardrobeRepo(pool),
		Outfits:  db.NewOutfitRepo(pool),
		Chats:    chats,
		Apple:    auth.NewAppleVerifier(cfg.AppleBundleID),
		Signer:   auth.NewSigner(cfg.JWTSigningSecret, cfg.SessionTTLHours),
		Gemini:   geminiClient,
		Storage:  store,
		Realtime: rdb,
		Gateway:  gateway,
	}

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           httpapi.NewRouter(deps),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       45 * time.Second,
		WriteTimeout:      120 * time.Second, // /v1/tryon Gemini call can run ~30–90s
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		slog.Info("http listen", "addr", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("http serve", "err", err.Error())
			cancel()
		}
	}()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	select {
	case <-sig:
		slog.Info("shutdown signal received")
	case <-ctx.Done():
	}

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	_ = srv.Shutdown(shutdownCtx)
	if err := riverClient.Stop(shutdownCtx); err != nil {
		slog.Warn("river stop", "err", err.Error())
	}
	slog.Info("bye")
}
