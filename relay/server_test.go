package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

const testToken = "0123456789abcdef"

func TestQuotesAuthenticationValidationAndContentType(t *testing.T) {
	h := readyHub([]string{"bybit-linear"})
	server := testAPIServer(h)

	request := httptest.NewRequest(http.MethodGet, "/v1/quotes?symbols=BTC", nil)
	request.RemoteAddr = "127.0.0.1:1234"
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d, want 401", response.Code)
	}

	request = authorizedRequest("/v1/quotes?symbols=b,ETH")
	response = httptest.NewRecorder()
	server.ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status=%d, want 400", response.Code)
	}
	if got := response.Header().Get("Content-Type"); got != "application/json; charset=utf-8" {
		t.Fatalf("content-type=%q", got)
	}
}

func TestQuotesReturnsSelectedMemoryQuote(t *testing.T) {
	now := time.Unix(3000, 0)
	h := newHub([]string{"bybit-linear", "binance-futures"}, func() time.Time { return now })
	h.setCatalog("bybit-linear", setOf("BTC"))
	h.setCatalog("binance-futures", setOf("BTC"))
	h.setConnected("bybit-linear", true)
	price, high, low := 62000.1, 63000.0, 60000.0
	h.updateQuote("bybit-linear", quoteUpdate{symbol: "BTC", price: &price, high24h: &high, low24h: &low})

	server := testAPIServer(h)
	server.now = func() time.Time { return now }
	request := authorizedRequest("/v1/quotes?symbols=btc,BTC")
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", response.Code, response.Body.String())
	}
	var body quoteResponse
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Quotes) != 1 || body.Quotes["BTC"].Source != "bybit-linear" || body.Quotes["BTC"].Price != price {
		t.Fatalf("body=%+v", body)
	}
}

func TestQuotesDistinguishesUnknownAndUnavailable(t *testing.T) {
	unknownHub := readyHub([]string{"bybit-linear"})
	unknownServer := testAPIServer(unknownHub)
	response := httptest.NewRecorder()
	unknownServer.ServeHTTP(response, authorizedRequest("/v1/quotes?symbols=UNKNOWN"))
	if response.Code != http.StatusOK {
		t.Fatalf("unknown status=%d", response.Code)
	}

	unresolvedHub := newHub([]string{"bybit-linear", "binance-futures"}, time.Now)
	unresolvedHub.setCatalog("bybit-linear", setOf())
	unresolvedServer := testAPIServer(unresolvedHub)
	unresolvedServer.quoteWait = time.Millisecond
	response = httptest.NewRecorder()
	unresolvedServer.ServeHTTP(response, authorizedRequest("/v1/quotes?symbols=BTC"))
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("unresolved status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestQuotesRateLimit(t *testing.T) {
	server := testAPIServer(readyHub([]string{"bybit-linear"}))
	for i := 0; i < 4; i++ {
		response := httptest.NewRecorder()
		server.ServeHTTP(response, authorizedRequest("/v1/quotes?symbols=UNKNOWN"))
		want := http.StatusOK
		if i == 3 {
			want = http.StatusTooManyRequests
		}
		if response.Code != want {
			t.Fatalf("request %d status=%d, want %d", i+1, response.Code, want)
		}
	}
}

func TestParseSymbols(t *testing.T) {
	symbols, err := parseSymbols("btc, ETH,btc")
	if err != nil {
		t.Fatal(err)
	}
	assertStrings(t, symbols, []string{"BTC", "ETH"})
	tooMany := make([]string, maxRequestSymbols+1)
	for i := range tooMany {
		tooMany[i] = fmt.Sprintf("S%02d", i)
	}
	if _, err := parseSymbols(strings.Join(tooMany, ",")); err == nil {
		t.Fatal("too many symbols accepted")
	}
}

func readyHub(sources []string) *hub {
	h := newHub(sources, time.Now)
	for _, source := range sources {
		h.setCatalog(source, setOf())
	}
	return h
}

func testAPIServer(h *hub) *apiServer {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	server := newAPIServer(h, nil, sha256.Sum256([]byte(testToken)), logger)
	server.quoteWait = time.Millisecond
	server.handlerTimeout = 10 * time.Millisecond
	return server
}

func authorizedRequest(target string) *http.Request {
	request := httptest.NewRequest(http.MethodGet, target, nil)
	request.RemoteAddr = "127.0.0.1:1234"
	request.Header.Set("Authorization", "Bearer "+testToken)
	return request
}
