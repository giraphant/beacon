package main

import (
	"crypto/sha256"
	"fmt"
	"os"
	"strings"
)

const defaultSources = "bybit-linear,binance-futures,binance-spot"

type config struct {
	listenAddr string
	tokenHash  [sha256.Size]byte
	sources    []string
}

func loadConfig() (config, error) {
	return loadConfigFrom(os.Getenv)
}

func loadConfigFrom(getenv func(string) string) (config, error) {
	token := getenv("RELAY_TOKEN")
	if len(token) < 16 {
		return config{}, fmt.Errorf("RELAY_TOKEN must contain at least 16 characters")
	}

	listenAddr := strings.TrimSpace(getenv("LISTEN_ADDR"))
	if listenAddr == "" {
		listenAddr = ":18765"
	}

	rawSources := strings.TrimSpace(getenv("SOURCES"))
	if rawSources == "" {
		rawSources = defaultSources
	}

	known := map[string]struct{}{
		"bybit-linear":    {},
		"binance-futures": {},
		"binance-spot":    {},
	}
	seen := make(map[string]struct{})
	sources := make([]string, 0, 3)
	for _, raw := range strings.Split(rawSources, ",") {
		id := strings.TrimSpace(raw)
		if _, ok := known[id]; !ok {
			return config{}, fmt.Errorf("unknown source %q", id)
		}
		if _, duplicate := seen[id]; duplicate {
			return config{}, fmt.Errorf("duplicate source %q", id)
		}
		seen[id] = struct{}{}
		sources = append(sources, id)
	}
	if len(sources) == 0 {
		return config{}, fmt.Errorf("SOURCES must enable at least one source")
	}

	return config{
		listenAddr: listenAddr,
		tokenHash:  sha256.Sum256([]byte(token)),
		sources:    sources,
	}, nil
}
