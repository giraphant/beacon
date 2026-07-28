package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

const (
	binanceFuturesCatalog = "https://fapi.binance.com/fapi/v1/exchangeInfo"
	binanceFuturesWS      = "wss://fstream.binance.com/market/stream"
	binanceSpotCatalog    = "https://api.binance.com/api/v3/exchangeInfo?symbolStatus=TRADING&showPermissionSets=false"
	binanceSpotWS         = "wss://stream.binance.com:9443/ws"
)

type binanceAdapter struct {
	id           string
	client       *http.Client
	catalogURL   string
	websocket    string
	contractType string
}

func newBinanceFuturesAdapter() *binanceAdapter {
	return &binanceAdapter{
		id:           "binance-futures",
		client:       &http.Client{Timeout: 10 * time.Second},
		catalogURL:   binanceFuturesCatalog,
		websocket:    binanceFuturesWS,
		contractType: "PERPETUAL",
	}
}

func newBinanceSpotAdapter() *binanceAdapter {
	return &binanceAdapter{
		id:         "binance-spot",
		client:     &http.Client{Timeout: 10 * time.Second},
		catalogURL: binanceSpotCatalog,
		websocket:  binanceSpotWS,
	}
}

func (a *binanceAdapter) ID() string { return a.id }

func (a *binanceAdapter) LoadCatalog(ctx context.Context) (map[string]struct{}, error) {
	var response struct {
		Symbols []struct {
			Symbol       string `json:"symbol"`
			BaseAsset    string `json:"baseAsset"`
			QuoteAsset   string `json:"quoteAsset"`
			Status       string `json:"status"`
			ContractType string `json:"contractType"`
		} `json:"symbols"`
	}
	if err := fetchJSON(ctx, a.client, a.catalogURL, &response); err != nil {
		return nil, err
	}

	catalog := make(map[string]struct{})
	for _, instrument := range response.Symbols {
		if instrument.Status != "TRADING" || instrument.QuoteAsset != "USDT" {
			continue
		}
		if a.contractType != "" && instrument.ContractType != a.contractType {
			continue
		}
		base := strings.ToUpper(instrument.BaseAsset)
		if instrument.Symbol == base+"USDT" {
			catalog[base] = struct{}{}
		}
	}
	return catalog, nil
}

func (a *binanceAdapter) Dial(ctx context.Context) (sourceStream, error) {
	conn, err := dialWebSocket(ctx, a.websocket)
	if err != nil {
		return nil, err
	}
	return &binanceStream{websocketConn: conn}, nil
}

type binanceStream struct {
	*websocketConn
	nextID int64
}

func (s *binanceStream) Subscribe(symbols []string) error {
	params := make([]string, 0, len(symbols))
	for _, symbol := range symbols {
		params = append(params, strings.ToLower(symbol)+"usdt@ticker")
	}
	s.nextID++
	return s.writeJSON(map[string]any{
		"method": "SUBSCRIBE",
		"params": params,
		"id":     s.nextID,
	})
}

func (s *binanceStream) Ping() error {
	return s.pingControl()
}

func (s *binanceStream) Read() (*quoteUpdate, error) {
	data, err := s.readMessage()
	if err != nil {
		return nil, err
	}
	return parseBinanceMessage(data)
}

func parseBinanceMessage(data []byte) (*quoteUpdate, error) {
	fields, err := decodeBinanceObject(data)
	if err != nil {
		return nil, err
	}
	if streamRaw, ok := fields["stream"]; ok {
		var stream string
		if err := json.Unmarshal(streamRaw, &stream); err != nil {
			return nil, fmt.Errorf("binance combined stream: %w", err)
		}
		if stream == "" {
			return nil, nil
		}
		dataRaw, ok := fields["data"]
		if !ok {
			return nil, nil
		}
		fields, err = decodeBinanceObject(dataRaw)
		if err != nil {
			return nil, fmt.Errorf("binance combined data: %w", err)
		}
		if fields == nil {
			return nil, nil
		}
	}

	if codeRaw, ok := fields["code"]; ok {
		var code int
		if err := json.Unmarshal(codeRaw, &code); err != nil {
			return nil, err
		}
		msg, err := binanceStringField(fields, "msg")
		if err != nil {
			return nil, err
		}
		return nil, fmt.Errorf("binance subscription failed: %s (%d)", msg, code)
	}

	eventRaw, ok := fields["e"]
	if !ok {
		return nil, nil
	}
	var event string
	if err := json.Unmarshal(eventRaw, &event); err != nil || event != "24hrTicker" {
		return nil, nil
	}

	symbol, err := binanceStringField(fields, "s")
	if err != nil {
		return nil, err
	}
	base, ok := baseFromUSDT(symbol)
	if !ok {
		return nil, nil
	}
	closeRaw, err := binanceStringField(fields, "c")
	if err != nil {
		return nil, err
	}
	highRaw, err := binanceStringField(fields, "h")
	if err != nil {
		return nil, err
	}
	lowRaw, err := binanceStringField(fields, "l")
	if err != nil {
		return nil, err
	}
	price, err := requiredPositiveFloat(closeRaw)
	if err != nil {
		return nil, fmt.Errorf("binance %s price: %w", symbol, err)
	}
	high, err := requiredPositiveFloat(highRaw)
	if err != nil {
		return nil, fmt.Errorf("binance %s high: %w", symbol, err)
	}
	low, err := requiredPositiveFloat(lowRaw)
	if err != nil {
		return nil, fmt.Errorf("binance %s low: %w", symbol, err)
	}
	return &quoteUpdate{symbol: base, price: price, high24h: high, low24h: low}, nil
}

// Binance ticker payloads intentionally contain case-distinct keys such as e/E, c/C, and l/L.
// A RawMessage map preserves exact JSON key matching; struct decoding does not.
func decodeBinanceObject(data []byte) (map[string]json.RawMessage, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return nil, err
	}
	return fields, nil
}

func binanceStringField(fields map[string]json.RawMessage, key string) (string, error) {
	raw, ok := fields[key]
	if !ok {
		return "", nil
	}
	var value string
	if err := json.Unmarshal(raw, &value); err != nil {
		return "", fmt.Errorf("binance field %q: %w", key, err)
	}
	return value, nil
}

func requiredPositiveFloat(raw string) (*float64, error) {
	value, err := optionalPositiveFloat(raw)
	if err != nil {
		return nil, err
	}
	if value == nil {
		return nil, fmt.Errorf("value is required")
	}
	return value, nil
}
