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

func TestBinanceFuturesUsesDocumentedMarketStreamEndpoint(t *testing.T) {
	if got := newBinanceFuturesAdapter().websocket; got != "wss://fstream.binance.com/market/stream" {
		t.Fatalf("websocket=%q, want routed market endpoint", got)
	}
}

func TestBinanceTickerParserHandlesDocumentedCaseCollisions(t *testing.T) {
	const event = `{"e":"24hrTicker","E":1785271763581,"s":"BTCUSDT","p":"-487.30","P":"-0.756","w":"63801.28","c":"63920.10","Q":"0.001","o":"64407.40","h":"64942.40","l":"62660.10","v":"182304.57","q":"11631449302.42","O":1785185363581,"C":1785271763581,"F":723456789,"L":723987654,"n":530866,"ps":"BTCUSDT","st":1}`
	tests := []struct {
		name string
		raw  string
	}{
		{name: "raw", raw: event},
		{name: "combined", raw: `{"stream":"btcusdt@ticker","data":` + event + `}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			quote, err := parseBinanceMessage([]byte(tt.raw))
			if err != nil {
				t.Fatal(err)
			}
			if quote == nil {
				t.Fatal("ticker was dropped")
			}
			if quote.symbol != "BTC" || quote.price == nil || *quote.price != 63920.1 || quote.high24h == nil || *quote.high24h != 64942.4 || quote.low24h == nil || *quote.low24h != 62660.1 {
				t.Fatalf("quote=%+v", quote)
			}
		})
	}
}

func TestBinanceTickerParserRequiresExactCombinedEnvelopeKeys(t *testing.T) {
	for _, raw := range []string{
		`{"stream":"btcusdt@ticker"}`,
		`{"stream":"btcusdt@ticker","data":null}`,
		`{"stream":"btcusdt@ticker","data":{"E":1785271763581,"s":"BTCUSDT","c":"1","h":"2","l":"0.5"}}`,
		`{"stream":"btcusdt@ticker","Data":{"e":"24hrTicker","s":"BTCUSDT","c":"1","h":"2","l":"0.5"}}`,
		`{"Stream":"btcusdt@ticker","Data":{"e":"24hrTicker","s":"BTCUSDT","c":"1","h":"2","l":"0.5"}}`,
	} {
		quote, err := parseBinanceMessage([]byte(raw))
		if err != nil || quote != nil {
			t.Fatalf("malformed combined envelope accepted: quote=%v err=%v raw=%s", quote, err, raw)
		}
	}

	for _, raw := range []string{
		`{"stream":1,"data":{}}`,
		`{"stream":"btcusdt@ticker","data":[]}`,
	} {
		if quote, err := parseBinanceMessage([]byte(raw)); err == nil || quote != nil {
			t.Fatalf("malformed combined envelope was not rejected: quote=%v err=%v raw=%s", quote, err, raw)
		}
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

	unchanged, err := parseBybitMessage([]byte(`{"topic":"tickers.BTCUSDT","type":"delta","data":{"symbol":"BTCUSDT","markPrice":"62001"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if unchanged == nil || unchanged.symbol != "BTC" || unchanged.price != nil || unchanged.high24h != nil || unchanged.low24h != nil {
		t.Fatalf("unchanged delta=%+v", unchanged)
	}

	for _, raw := range []string{
		`{"topic":"tickers.BTCUSDT"}`,
		`{"topic":"tickers.BTCUSDT","type":"heartbeat","data":{"symbol":"BTCUSDT"}}`,
		`{"topic":"tickers.BTCUSDT","type":"snapshot","data":{"symbol":"BTCUSDT","markPrice":"62001"}}`,
	} {
		unknown, err := parseBybitMessage([]byte(raw))
		if err != nil || unknown != nil {
			t.Fatalf("non-ticker-state message: update=%v err=%v", unknown, err)
		}
	}

	binance, err := parseBinanceMessage([]byte(`{"e":"24hrTicker","s":"ETHUSDT","c":"3500","h":"3600","l":"3400"}`))
	if err != nil {
		t.Fatal(err)
	}
	if binance == nil || binance.symbol != "ETH" || *binance.low24h != 3400 {
		t.Fatalf("binance=%+v", binance)
	}

	combined, err := parseBinanceMessage([]byte(`{"stream":"ethusdt@ticker","data":{"e":"24hrTicker","s":"ETHUSDT","c":"3501","h":"3600","l":"3400"}}`))
	if err != nil {
		t.Fatal(err)
	}
	if combined == nil || combined.symbol != "ETH" || *combined.price != 3501 {
		t.Fatalf("combined binance=%+v", combined)
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
