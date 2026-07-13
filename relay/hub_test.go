package main

import (
	"errors"
	"fmt"
	"testing"
	"time"
)

func TestHubClassifiesAndSubscribesSymbols(t *testing.T) {
	now := time.Unix(1000, 0)
	h := newHub([]string{"bybit-linear", "binance-futures", "binance-spot"}, func() time.Time { return now })
	h.setCatalog("bybit-linear", setOf("BTC"))
	h.setCatalog("binance-futures", setOf("BTC", "ETH"))
	h.setCatalog("binance-spot", setOf("SOL"))

	plan, err := h.prepare([]string{"BTC", "ETH", "UNKNOWN"})
	if err != nil {
		t.Fatal(err)
	}
	assertStrings(t, plan.known, []string{"BTC", "ETH"})
	assertStrings(t, plan.unknown, []string{"UNKNOWN"})
	assertStrings(t, plan.subscriptions["bybit-linear"], []string{"BTC"})
	assertStrings(t, plan.subscriptions["binance-futures"], []string{"BTC", "ETH"})
	if len(h.requested) != 2 {
		t.Fatalf("requested=%d, want 2", len(h.requested))
	}
}

func TestHubLeavesSymbolUnresolvedUntilCatalogsReady(t *testing.T) {
	h := newHub([]string{"bybit-linear", "binance-futures"}, time.Now)
	h.setCatalog("bybit-linear", setOf())

	plan, err := h.prepare([]string{"BTC"})
	if err != nil {
		t.Fatal(err)
	}
	assertStrings(t, plan.unresolved, []string{"BTC"})
	if len(h.requested) != 0 {
		t.Fatal("unresolved symbol consumed the instance limit")
	}
}

func TestHubAppliesInstanceLimitTransactionally(t *testing.T) {
	h := newHub([]string{"bybit-linear"}, time.Now)
	catalog := make(map[string]struct{}, maxSymbols+1)
	for i := 0; i <= maxSymbols; i++ {
		catalog[fmt.Sprintf("S%03d", i)] = struct{}{}
	}
	h.setCatalog("bybit-linear", catalog)
	for i := 0; i < maxSymbols; i++ {
		h.requested[fmt.Sprintf("S%03d", i)] = struct{}{}
	}

	_, err := h.prepare([]string{"S100"})
	if !errors.Is(err, errSymbolLimit) {
		t.Fatalf("err=%v, want errSymbolLimit", err)
	}
	if len(h.requested) != maxSymbols {
		t.Fatalf("requested=%d, want %d", len(h.requested), maxSymbols)
	}
}

func TestHubMergesDeltaAndPrefersFreshSource(t *testing.T) {
	now := time.Unix(2000, 0)
	h := newHub([]string{"bybit-linear", "binance-futures"}, func() time.Time { return now })
	h.setConnected("bybit-linear", true)
	h.setConnected("binance-futures", true)

	price, high, low := 100.0, 110.0, 90.0
	h.updateQuote("bybit-linear", quoteUpdate{symbol: "BTC", price: &price, high24h: &high, low24h: &low})
	price = 101
	h.updateQuote("bybit-linear", quoteUpdate{symbol: "BTC", price: &price})
	binancePrice, binanceHigh, binanceLow := 102.0, 112.0, 92.0
	h.updateQuote("binance-futures", quoteUpdate{symbol: "BTC", price: &binancePrice, high24h: &binanceHigh, low24h: &binanceLow})

	quotes, missing := h.selectQuotes([]string{"BTC"})
	if len(missing) != 0 {
		t.Fatalf("missing=%v", missing)
	}
	if quotes["BTC"].Source != "bybit-linear" || quotes["BTC"].Price != 101 || quotes["BTC"].High24h != 110 {
		t.Fatalf("unexpected merged quote: %+v", quotes["BTC"])
	}

	h.setConnected("bybit-linear", false)
	quotes, _ = h.selectQuotes([]string{"BTC"})
	if quotes["BTC"].Source != "binance-futures" || quotes["BTC"].Stale {
		t.Fatalf("fresh fallback=%+v", quotes["BTC"])
	}

	h.setConnected("binance-futures", false)
	quotes, _ = h.selectQuotes([]string{"BTC"})
	if quotes["BTC"].Source != "bybit-linear" || !quotes["BTC"].Stale {
		t.Fatalf("stale priority=%+v", quotes["BTC"])
	}

	now = now.Add(maxQuoteAge + time.Second)
	quotes, missing = h.selectQuotes([]string{"BTC"})
	if len(quotes) != 0 || len(missing) != 1 {
		t.Fatalf("expired quotes=%v missing=%v", quotes, missing)
	}
}

func TestHubRejectsInvalidUpdateWithoutOverwritingCache(t *testing.T) {
	now := time.Unix(4000, 0)
	h := newHub([]string{"bybit-linear"}, func() time.Time { return now })
	h.setConnected("bybit-linear", true)
	price, high, low := 100.0, 110.0, 90.0
	h.updateQuote("bybit-linear", quoteUpdate{symbol: "BTC", price: &price, high24h: &high, low24h: &low})

	invalid := -1.0
	if h.updateQuote("bybit-linear", quoteUpdate{symbol: "BTC", price: &invalid}) {
		t.Fatal("invalid update accepted")
	}
	quotes, _ := h.selectQuotes([]string{"BTC"})
	if quotes["BTC"].Price != price {
		t.Fatalf("price=%v, want %v", quotes["BTC"].Price, price)
	}
}

func setOf(values ...string) map[string]struct{} {
	set := make(map[string]struct{}, len(values))
	for _, value := range values {
		set[value] = struct{}{}
	}
	return set
}

func assertStrings(t *testing.T, got, want []string) {
	t.Helper()
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}
