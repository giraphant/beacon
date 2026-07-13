package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("relay stopped", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	hub := newHub(cfg.sources, time.Now)
	adapters := map[string]sourceAdapter{
		"bybit-linear":    newBybitAdapter(),
		"binance-futures": newBinanceFuturesAdapter(),
		"binance-spot":    newBinanceSpotAdapter(),
	}
	subscribers := make(map[string]func([]string), len(cfg.sources))
	for _, id := range cfg.sources {
		runner := newSourceRunner(adapters[id], hub, logger)
		subscribers[id] = runner.AddSubscriptions
		go runner.Run(ctx)
	}

	api := newAPIServer(hub, subscribers, cfg.tokenHash, logger)
	server := &http.Server{
		Addr:              cfg.listenAddr,
		Handler:           api,
		ReadHeaderTimeout: 2 * time.Second,
		ReadTimeout:       3 * time.Second,
		WriteTimeout:      4 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    8 << 10,
	}

	serverErrors := make(chan error, 1)
	go func() {
		logger.Info("relay listening", "address", cfg.listenAddr, "sources", cfg.sources)
		serverErrors <- server.ListenAndServe()
	}()
	go logStats(ctx, hub, api, logger)

	select {
	case <-ctx.Done():
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			cancel()
			return err
		}
	}

	cancel()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		return err
	}
	return nil
}

func logStats(ctx context.Context, hub *hub, api *apiServer, logger *slog.Logger) {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			for _, stat := range hub.stats() {
				logger.Info("source status",
					"source", stat.ID,
					"connected", stat.Connected,
					"catalog_ready", stat.CatalogReady,
					"last_message_age_ms", stat.LastMessageAgeMS,
					"subscriptions", stat.SubscriptionCount,
					"reconnects", stat.Reconnects,
					"http_5xx", api.http5xx.Load(),
				)
			}
		}
	}
}
