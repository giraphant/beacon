package main

import "testing"

func TestLoadConfigDefaultsAndValidation(t *testing.T) {
	values := map[string]string{"RELAY_TOKEN": testToken}
	cfg, err := loadConfigFrom(func(key string) string { return values[key] })
	if err != nil {
		t.Fatal(err)
	}
	if cfg.listenAddr != ":18765" {
		t.Fatalf("listenAddr=%q", cfg.listenAddr)
	}
	assertStrings(t, cfg.sources, []string{"bybit-linear", "binance-futures", "binance-spot"})

	values["SOURCES"] = "binance-spot,unknown"
	if _, err := loadConfigFrom(func(key string) string { return values[key] }); err == nil {
		t.Fatal("unknown source accepted")
	}
	values["SOURCES"] = "bybit-linear"
	values["RELAY_TOKEN"] = "short"
	if _, err := loadConfigFrom(func(key string) string { return values[key] }); err == nil {
		t.Fatal("short token accepted")
	}
}
