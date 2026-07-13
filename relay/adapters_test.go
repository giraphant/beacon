package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

func TestBybitCatalogPaginationAndFiltering(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("cursor") == "" {
			fmt.Fprint(w, `{"retCode":0,"result":{"list":[{"symbol":"BTCUSDT","baseCoin":"BTC","quoteCoin":"USDT","status":"Trading","contractType":"LinearPerpetual"},{"symbol":"1000BONKUSDT","baseCoin":"BONK","quoteCoin":"USDT","status":"Trading","contractType":"LinearPerpetual"}],"nextPageCursor":"next"}}`)
			return
		}
		fmt.Fprint(w, `{"retCode":0,"result":{"list":[{"symbol":"ETHUSDT","baseCoin":"ETH","quoteCoin":"USDT","status":"Trading","contractType":"LinearPerpetual"},{"symbol":"SOLUSDC","baseCoin":"SOL","quoteCoin":"USDC","status":"Trading","contractType":"LinearPerpetual"}],"nextPageCursor":""}}`)
	}))
	defer server.Close()

	adapter := newBybitAdapter()
	adapter.client = server.Client()
	adapter.catalogURL = server.URL
	catalog, err := adapter.LoadCatalog(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := catalog["BTC"]; !ok {
		t.Fatal("BTC missing")
	}
	if _, ok := catalog["ETH"]; !ok {
		t.Fatal("ETH missing")
	}
	if _, ok := catalog["BONK"]; ok {
		t.Fatal("multiplier contract should not be mapped")
	}
	if len(catalog) != 2 {
		t.Fatalf("catalog=%v", catalog)
	}
}

func TestBinanceCatalogFiltersMarketType(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprint(w, `{"symbols":[{"symbol":"BTCUSDT","baseAsset":"BTC","quoteAsset":"USDT","status":"TRADING","contractType":"PERPETUAL"},{"symbol":"ETHUSDT","baseAsset":"ETH","quoteAsset":"USDT","status":"TRADING","contractType":"CURRENT_QUARTER"},{"symbol":"SOLUSDC","baseAsset":"SOL","quoteAsset":"USDC","status":"TRADING","contractType":"PERPETUAL"}]}`)
	}))
	defer server.Close()

	adapter := newBinanceFuturesAdapter()
	adapter.client = server.Client()
	adapter.catalogURL = server.URL
	catalog, err := adapter.LoadCatalog(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(catalog) != 1 {
		t.Fatalf("catalog=%v", catalog)
	}
	if _, ok := catalog["BTC"]; !ok {
		t.Fatal("BTC missing")
	}
}

func TestBinanceSpotCatalogRequestsOnlyTradingSymbols(t *testing.T) {
	endpoint, err := url.Parse(binanceSpotCatalog)
	if err != nil {
		t.Fatal(err)
	}
	query := endpoint.Query()
	if query.Get("symbolStatus") != "TRADING" || query.Get("showPermissionSets") != "false" {
		t.Fatalf("unexpected query: %s", endpoint.RawQuery)
	}
}

func TestTickerParsers(t *testing.T) {
	bybit, err := parseBybitMessage([]byte(`{"topic":"tickers.BTCUSDT","type":"snapshot","data":{"symbol":"BTCUSDT","lastPrice":"62000.1","highPrice24h":"63000","lowPrice24h":"60000"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if bybit == nil || bybit.symbol != "BTC" || *bybit.price != 62000.1 || *bybit.high24h != 63000 {
		t.Fatalf("bybit=%+v", bybit)
	}

	delta, err := parseBybitMessage([]byte(`{"topic":"tickers.BTCUSDT","type":"delta","data":{"symbol":"BTCUSDT","lastPrice":"62001"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if delta == nil || delta.high24h != nil || *delta.price != 62001 {
		t.Fatalf("delta=%+v", delta)
	}

	binance, err := parseBinanceMessage([]byte(`{"e":"24hrTicker","s":"ETHUSDT","c":"3500","h":"3600","l":"3400"}`))
	if err != nil {
		t.Fatal(err)
	}
	if binance == nil || binance.symbol != "ETH" || *binance.low24h != 3400 {
		t.Fatalf("binance=%+v", binance)
	}

	if _, err := parseBinanceMessage([]byte(`{"e":"24hrTicker","s":"ETHUSDT","c":"bad","h":"3600","l":"3400"}`)); err == nil {
		t.Fatal("invalid price accepted")
	}
	for _, raw := range []string{`{"e":1,"id":1}`, `{"e":"subscriptionResponse","c":1}`} {
		unknown, err := parseBinanceMessage([]byte(raw))
		if err != nil || unknown != nil {
			t.Fatalf("unknown control message: update=%v err=%v", unknown, err)
		}
	}
}
