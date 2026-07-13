package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const (
	bybitCatalogURL = "https://api.bybit.com/v5/market/instruments-info"
	bybitWebSocket  = "wss://stream.bybit.com/v5/public/linear"
)

type bybitAdapter struct {
	client     *http.Client
	catalogURL string
	websocket  string
}

func newBybitAdapter() *bybitAdapter {
	return &bybitAdapter{
		client:     &http.Client{Timeout: 10 * time.Second},
		catalogURL: bybitCatalogURL,
		websocket:  bybitWebSocket,
	}
}

func (a *bybitAdapter) ID() string { return "bybit-linear" }

func (a *bybitAdapter) LoadCatalog(ctx context.Context) (map[string]struct{}, error) {
	catalog := make(map[string]struct{})
	cursor := ""
	seen := make(map[string]struct{})

	for {
		endpoint, err := url.Parse(a.catalogURL)
		if err != nil {
			return nil, err
		}
		query := endpoint.Query()
		query.Set("category", "linear")
		query.Set("limit", "1000")
		if cursor != "" {
			query.Set("cursor", cursor)
		}
		endpoint.RawQuery = query.Encode()

		var response struct {
			RetCode int    `json:"retCode"`
			RetMsg  string `json:"retMsg"`
			Result  struct {
				List []struct {
					Symbol       string `json:"symbol"`
					BaseCoin     string `json:"baseCoin"`
					QuoteCoin    string `json:"quoteCoin"`
					Status       string `json:"status"`
					ContractType string `json:"contractType"`
				} `json:"list"`
				NextPageCursor string `json:"nextPageCursor"`
			} `json:"result"`
		}
		if err := fetchJSON(ctx, a.client, endpoint.String(), &response); err != nil {
			return nil, err
		}
		if response.RetCode != 0 {
			return nil, fmt.Errorf("bybit catalog: %s (%d)", response.RetMsg, response.RetCode)
		}

		for _, instrument := range response.Result.List {
			if instrument.Status != "Trading" || instrument.QuoteCoin != "USDT" || instrument.ContractType != "LinearPerpetual" {
				continue
			}
			base := strings.ToUpper(instrument.BaseCoin)
			if instrument.Symbol == base+"USDT" {
				catalog[base] = struct{}{}
			}
		}

		next := response.Result.NextPageCursor
		if next == "" {
			break
		}
		if _, duplicate := seen[next]; duplicate {
			return nil, fmt.Errorf("bybit catalog repeated cursor")
		}
		seen[next] = struct{}{}
		cursor = next
	}
	return catalog, nil
}

func (a *bybitAdapter) Dial(ctx context.Context) (sourceStream, error) {
	conn, err := dialWebSocket(ctx, a.websocket)
	if err != nil {
		return nil, err
	}
	return &bybitStream{websocketConn: conn}, nil
}

type bybitStream struct {
	*websocketConn
}

func (s *bybitStream) Subscribe(symbols []string) error {
	topics := make([]string, 0, len(symbols))
	for _, symbol := range symbols {
		topics = append(topics, "tickers."+symbol+"USDT")
	}
	return s.writeJSON(map[string]any{"op": "subscribe", "args": topics})
}

func (s *bybitStream) Ping() error {
	return s.writeJSON(map[string]string{"op": "ping"})
}

func (s *bybitStream) Read() (*quoteUpdate, error) {
	data, err := s.readMessage()
	if err != nil {
		return nil, err
	}
	return parseBybitMessage(data)
}

func parseBybitMessage(data []byte) (*quoteUpdate, error) {
	var message struct {
		Success *bool  `json:"success"`
		RetMsg  string `json:"ret_msg"`
		Op      string `json:"op"`
		Topic   string `json:"topic"`
		Data    struct {
			Symbol       string `json:"symbol"`
			LastPrice    string `json:"lastPrice"`
			HighPrice24h string `json:"highPrice24h"`
			LowPrice24h  string `json:"lowPrice24h"`
		} `json:"data"`
	}
	if err := json.Unmarshal(data, &message); err != nil {
		return nil, err
	}
	if message.Success != nil && !*message.Success {
		return nil, fmt.Errorf("bybit %s failed: %s", message.Op, message.RetMsg)
	}
	if !strings.HasPrefix(message.Topic, "tickers.") {
		return nil, nil
	}

	upstreamSymbol := message.Data.Symbol
	if upstreamSymbol == "" {
		upstreamSymbol = strings.TrimPrefix(message.Topic, "tickers.")
	}
	base, ok := baseFromUSDT(upstreamSymbol)
	if !ok {
		return nil, nil
	}

	price, err := optionalPositiveFloat(message.Data.LastPrice)
	if err != nil {
		return nil, fmt.Errorf("bybit %s lastPrice: %w", upstreamSymbol, err)
	}
	high, err := optionalPositiveFloat(message.Data.HighPrice24h)
	if err != nil {
		return nil, fmt.Errorf("bybit %s highPrice24h: %w", upstreamSymbol, err)
	}
	low, err := optionalPositiveFloat(message.Data.LowPrice24h)
	if err != nil {
		return nil, fmt.Errorf("bybit %s lowPrice24h: %w", upstreamSymbol, err)
	}
	if price == nil && high == nil && low == nil {
		return nil, nil
	}
	return &quoteUpdate{symbol: base, price: price, high24h: high, low24h: low}, nil
}

func optionalPositiveFloat(raw string) (*float64, error) {
	if raw == "" {
		return nil, nil
	}
	value, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return nil, err
	}
	if !validPrice(value) {
		return nil, fmt.Errorf("must be finite and positive")
	}
	return &value, nil
}

func baseFromUSDT(symbol string) (string, bool) {
	symbol = strings.ToUpper(symbol)
	if !strings.HasSuffix(symbol, "USDT") || len(symbol) <= len("USDT") {
		return "", false
	}
	return strings.TrimSuffix(symbol, "USDT"), true
}
