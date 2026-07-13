package main

import (
	"context"
	"errors"
	"math"
	"sort"
	"sync"
	"time"
)

const (
	freshQuoteAge = 30 * time.Second
	maxQuoteAge   = 120 * time.Second
	maxSymbols    = 100
)

var errSymbolLimit = errors.New("instance symbol limit exceeded")

type quoteUpdate struct {
	symbol  string
	price   *float64
	high24h *float64
	low24h  *float64
}

type quoteRecord struct {
	price     float64
	high24h   float64
	low24h    float64
	updatedAt time.Time
}

func (q quoteRecord) complete() bool {
	return validPrice(q.price) && validPrice(q.high24h) && validPrice(q.low24h) && !q.updatedAt.IsZero()
}

type selectedQuote struct {
	Price     float64 `json:"price"`
	High24h   float64 `json:"high24h"`
	Low24h    float64 `json:"low24h"`
	Source    string  `json:"source"`
	UpdatedAt int64   `json:"updatedAt"`
	Stale     bool    `json:"stale"`
}

type sourceState struct {
	catalogReady bool
	catalog      map[string]struct{}
	connected    bool
	quotes       map[string]quoteRecord
	lastMessage  time.Time
	reconnects   uint64
}

type requestPlan struct {
	known         []string
	unknown       []string
	unresolved    []string
	subscriptions map[string][]string
}

type sourceStat struct {
	ID                string
	Connected         bool
	CatalogReady      bool
	LastMessageAgeMS  int64
	SubscriptionCount int
	Reconnects        uint64
}

type hub struct {
	mu        sync.RWMutex
	order     []string
	sources   map[string]*sourceState
	requested map[string]struct{}
	changed   chan struct{}
	now       func() time.Time
}

func newHub(order []string, now func() time.Time) *hub {
	if now == nil {
		now = time.Now
	}
	sources := make(map[string]*sourceState, len(order))
	for _, id := range order {
		sources[id] = &sourceState{
			catalog: make(map[string]struct{}),
			quotes:  make(map[string]quoteRecord),
		}
	}
	return &hub{
		order:     append([]string(nil), order...),
		sources:   sources,
		requested: make(map[string]struct{}),
		changed:   make(chan struct{}),
		now:       now,
	}
}

func (h *hub) setCatalog(source string, catalog map[string]struct{}) []string {
	h.mu.Lock()
	defer h.mu.Unlock()

	state := h.sources[source]
	state.catalogReady = true
	state.catalog = cloneSet(catalog)

	supported := make([]string, 0)
	for symbol := range h.requested {
		if _, ok := state.catalog[symbol]; ok {
			supported = append(supported, symbol)
		}
	}
	sort.Strings(supported)
	h.signalLocked()
	return supported
}

func (h *hub) prepare(symbols []string) (requestPlan, error) {
	h.mu.Lock()
	defer h.mu.Unlock()

	plan := requestPlan{subscriptions: make(map[string][]string, len(h.order))}
	newSymbols := make(map[string]struct{})

	for _, symbol := range symbols {
		allReady := true
		supported := false
		for _, source := range h.order {
			state := h.sources[source]
			if !state.catalogReady {
				allReady = false
			}
			if _, ok := state.catalog[symbol]; ok {
				supported = true
				plan.subscriptions[source] = append(plan.subscriptions[source], symbol)
			}
		}

		switch {
		case supported:
			plan.known = append(plan.known, symbol)
			if _, exists := h.requested[symbol]; !exists {
				newSymbols[symbol] = struct{}{}
			}
		case allReady:
			plan.unknown = append(plan.unknown, symbol)
		default:
			plan.unresolved = append(plan.unresolved, symbol)
		}
	}

	if len(h.requested)+len(newSymbols) > maxSymbols {
		return requestPlan{}, errSymbolLimit
	}
	for symbol := range newSymbols {
		h.requested[symbol] = struct{}{}
	}
	return plan, nil
}

func (h *hub) setConnected(source string, connected bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	state := h.sources[source]
	if state.connected != connected {
		state.connected = connected
		h.signalLocked()
	}
}

func (h *hub) incrementReconnect(source string) uint64 {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.sources[source].reconnects++
	return h.sources[source].reconnects
}

func (h *hub) touchSourceMessage(source string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.sources[source].lastMessage = h.now()
}

func (h *hub) updateQuote(source string, update quoteUpdate) bool {
	if update.symbol == "" || !validOptionalPrice(update.price) || !validOptionalPrice(update.high24h) || !validOptionalPrice(update.low24h) {
		return false
	}
	if update.price == nil && update.high24h == nil && update.low24h == nil {
		return false
	}

	h.mu.Lock()
	defer h.mu.Unlock()
	state := h.sources[source]
	record := state.quotes[update.symbol]
	if update.price != nil {
		record.price = *update.price
	}
	if update.high24h != nil {
		record.high24h = *update.high24h
	}
	if update.low24h != nil {
		record.low24h = *update.low24h
	}
	record.updatedAt = h.now()
	state.quotes[update.symbol] = record
	h.signalLocked()
	return true
}

func (h *hub) waitForQuotes(ctx context.Context, symbols []string) {
	for {
		h.mu.RLock()
		ready := h.hasUsableQuotesLocked(symbols, h.now())
		changed := h.changed
		h.mu.RUnlock()
		if ready {
			return
		}

		select {
		case <-ctx.Done():
			return
		case <-changed:
		}
	}
}

func (h *hub) selectQuotes(symbols []string) (map[string]selectedQuote, []string) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	now := h.now()
	quotes := make(map[string]selectedQuote, len(symbols))
	missing := make([]string, 0)
	for _, symbol := range symbols {
		if quote, ok := h.selectQuoteLocked(symbol, now, false); ok {
			quotes[symbol] = quote
			continue
		}
		if quote, ok := h.selectQuoteLocked(symbol, now, true); ok {
			quotes[symbol] = quote
			continue
		}
		missing = append(missing, symbol)
	}
	return quotes, missing
}

func (h *hub) stats() []sourceStat {
	h.mu.RLock()
	defer h.mu.RUnlock()

	now := h.now()
	stats := make([]sourceStat, 0, len(h.order))
	for _, id := range h.order {
		state := h.sources[id]
		age := int64(-1)
		if !state.lastMessage.IsZero() {
			age = now.Sub(state.lastMessage).Milliseconds()
		}
		count := 0
		for symbol := range h.requested {
			if _, ok := state.catalog[symbol]; ok {
				count++
			}
		}
		stats = append(stats, sourceStat{
			ID:                id,
			Connected:         state.connected,
			CatalogReady:      state.catalogReady,
			LastMessageAgeMS:  age,
			SubscriptionCount: count,
			Reconnects:        state.reconnects,
		})
	}
	return stats
}

func (h *hub) hasUsableQuotesLocked(symbols []string, now time.Time) bool {
	for _, symbol := range symbols {
		usable := false
		for _, source := range h.order {
			record := h.sources[source].quotes[symbol]
			if record.complete() && now.Sub(record.updatedAt) <= maxQuoteAge {
				usable = true
				break
			}
		}
		if !usable {
			return false
		}
	}
	return true
}

func (h *hub) selectQuoteLocked(symbol string, now time.Time, stalePass bool) (selectedQuote, bool) {
	for _, source := range h.order {
		state := h.sources[source]
		record := state.quotes[symbol]
		if !record.complete() {
			continue
		}
		age := now.Sub(record.updatedAt)
		if age < 0 {
			age = 0
		}
		if !stalePass {
			if !state.connected || age > freshQuoteAge {
				continue
			}
		} else if age > maxQuoteAge {
			continue
		}
		return selectedQuote{
			Price:     record.price,
			High24h:   record.high24h,
			Low24h:    record.low24h,
			Source:    source,
			UpdatedAt: record.updatedAt.UnixMilli(),
			Stale:     stalePass,
		}, true
	}
	return selectedQuote{}, false
}

func (h *hub) signalLocked() {
	close(h.changed)
	h.changed = make(chan struct{})
}

func validPrice(value float64) bool {
	return value > 0 && !math.IsNaN(value) && !math.IsInf(value, 0)
}

func validOptionalPrice(value *float64) bool {
	return value == nil || validPrice(*value)
}

func cloneSet(input map[string]struct{}) map[string]struct{} {
	output := make(map[string]struct{}, len(input))
	for key := range input {
		output[key] = struct{}{}
	}
	return output
}
