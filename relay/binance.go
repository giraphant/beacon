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
	binanceFuturesWS      = "wss://fstream.binance.com/ws"
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
	var envelope struct {
		Event json.RawMessage `json:"e"`
		Code  *int            `json:"code"`
		Msg   string          `json:"msg"`
	}
	if err := json.Unmarshal(data, &envelope); err != nil {
		return nil, err
	}
	if envelope.Code != nil {
		return nil, fmt.Errorf("binance subscription failed: %s (%d)", envelope.Msg, *envelope.Code)
	}
	if len(envelope.Event) == 0 {
		return nil, nil
	}
	var event string
	if err := json.Unmarshal(envelope.Event, &event); err != nil || event != "24hrTicker" {
		return nil, nil
	}

	var message struct {
		Symbol string `json:"s"`
		Close  string `json:"c"`
		High   string `json:"h"`
		Low    string `json:"l"`
	}
	if err := json.Unmarshal(data, &message); err != nil {
		return nil, err
	}
	base, ok := baseFromUSDT(message.Symbol)
	if !ok {
		return nil, nil
	}
	price, err := requiredPositiveFloat(message.Close)
	if err != nil {
		return nil, fmt.Errorf("binance %s price: %w", message.Symbol, err)
	}
	high, err := requiredPositiveFloat(message.High)
	if err != nil {
		return nil, fmt.Errorf("binance %s high: %w", message.Symbol, err)
	}
	low, err := requiredPositiveFloat(message.Low)
	if err != nil {
		return nil, fmt.Errorf("binance %s low: %w", message.Symbol, err)
	}
	return &quoteUpdate{symbol: base, price: price, high24h: high, low24h: low}, nil
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
