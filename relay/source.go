package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math/rand"
	"net/http"
	"sort"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	catalogRefreshInterval = 6 * time.Hour
	catalogBodyLimit       = 8 << 20
	websocketMessageLimit  = 64 << 10
	connectionStableAfter  = 30 * time.Second
	pingInterval           = 20 * time.Second
	subscriptionBatchSize  = 50
)

type sourceAdapter interface {
	ID() string
	LoadCatalog(context.Context) (map[string]struct{}, error)
	Dial(context.Context) (sourceStream, error)
}

type sourceStream interface {
	Subscribe([]string) error
	Ping() error
	Read() (*quoteUpdate, error)
	Close() error
}

type sourceRunner struct {
	adapter sourceAdapter
	hub     *hub
	logger  *slog.Logger

	desiredMu sync.Mutex
	desired   map[string]struct{}
	wake      chan struct{}

	now       func() time.Time
	randFloat func() float64
}

func newSourceRunner(adapter sourceAdapter, hub *hub, logger *slog.Logger) *sourceRunner {
	return &sourceRunner{
		adapter:   adapter,
		hub:       hub,
		logger:    logger,
		desired:   make(map[string]struct{}),
		wake:      make(chan struct{}, 1),
		now:       time.Now,
		randFloat: rand.Float64,
	}
}

func (r *sourceRunner) AddSubscriptions(symbols []string) {
	if len(symbols) == 0 {
		return
	}
	r.desiredMu.Lock()
	for _, symbol := range symbols {
		r.desired[symbol] = struct{}{}
	}
	r.desiredMu.Unlock()
	select {
	case r.wake <- struct{}{}:
	default:
	}
}

func (r *sourceRunner) Run(ctx context.Context) {
	go r.catalogLoop(ctx)

	attempt := 0
	for ctx.Err() == nil {
		stream, err := r.adapter.Dial(ctx)
		if err == nil {
			started := r.now()
			r.logger.Info("source connected", "source", r.adapter.ID())
			err = r.runConnection(ctx, stream)
			if r.now().Sub(started) >= connectionStableAfter {
				attempt = 0
			}
		}
		if ctx.Err() != nil {
			return
		}

		r.hub.setConnected(r.adapter.ID(), false)
		reconnects := r.hub.incrementReconnect(r.adapter.ID())
		delay := backoffDelay(attempt, r.randFloat)
		attempt++
		r.logger.Warn("source disconnected", "source", r.adapter.ID(), "error", err, "retry_in_ms", delay.Milliseconds(), "reconnects", reconnects)
		if !sleepContext(ctx, delay) {
			return
		}
	}
}

func (r *sourceRunner) catalogLoop(ctx context.Context) {
	attempt := 0
	for ctx.Err() == nil {
		catalog, err := r.adapter.LoadCatalog(ctx)
		if err != nil {
			delay := backoffDelay(attempt, r.randFloat)
			attempt++
			r.logger.Warn("catalog refresh failed", "source", r.adapter.ID(), "error", err, "retry_in_ms", delay.Milliseconds())
			if !sleepContext(ctx, delay) {
				return
			}
			continue
		}

		attempt = 0
		supported := r.hub.setCatalog(r.adapter.ID(), catalog)
		r.AddSubscriptions(supported)
		r.logger.Info("catalog refreshed", "source", r.adapter.ID(), "symbols", len(catalog))
		if !sleepContext(ctx, catalogRefreshInterval) {
			return
		}
	}
}

func (r *sourceRunner) runConnection(ctx context.Context, stream sourceStream) error {
	r.hub.setConnected(r.adapter.ID(), true)
	runCtx, cancel := context.WithCancel(ctx)
	defer func() {
		cancel()
		_ = stream.Close()
		r.hub.setConnected(r.adapter.ID(), false)
	}()

	type readResult struct {
		update *quoteUpdate
		err    error
	}
	reads := make(chan readResult, 256)
	go func() {
		for {
			update, err := stream.Read()
			select {
			case reads <- readResult{update: update, err: err}:
			case <-runCtx.Done():
				return
			}
			if err != nil {
				return
			}
		}
	}()

	subscribed := make(map[string]struct{})
	if err := r.subscribeMissing(stream, subscribed); err != nil {
		return err
	}

	ping := time.NewTicker(pingInterval)
	defer ping.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case result := <-reads:
			if result.err != nil {
				return result.err
			}
			r.hub.touchSourceMessage(r.adapter.ID())
			if result.update != nil {
				r.hub.updateQuote(r.adapter.ID(), *result.update)
			}
		case <-r.wake:
			if err := r.subscribeMissing(stream, subscribed); err != nil {
				return err
			}
		case <-ping.C:
			if err := stream.Ping(); err != nil {
				return err
			}
		}
	}
}

func (r *sourceRunner) subscribeMissing(stream sourceStream, subscribed map[string]struct{}) error {
	desired := r.desiredSnapshot()
	missing := make([]string, 0, len(desired))
	for _, symbol := range desired {
		if _, ok := subscribed[symbol]; !ok {
			missing = append(missing, symbol)
		}
	}
	for start := 0; start < len(missing); start += subscriptionBatchSize {
		end := min(start+subscriptionBatchSize, len(missing))
		batch := missing[start:end]
		if err := stream.Subscribe(batch); err != nil {
			return fmt.Errorf("subscribe %s: %w", r.adapter.ID(), err)
		}
		for _, symbol := range batch {
			subscribed[symbol] = struct{}{}
		}
	}
	return nil
}

func (r *sourceRunner) desiredSnapshot() []string {
	r.desiredMu.Lock()
	defer r.desiredMu.Unlock()
	symbols := make([]string, 0, len(r.desired))
	for symbol := range r.desired {
		symbols = append(symbols, symbol)
	}
	sort.Strings(symbols)
	return symbols
}

func backoffDelay(attempt int, random func() float64) time.Duration {
	raw := 2 * time.Second
	for range min(attempt, 4) {
		raw *= 2
	}
	if raw > 30*time.Second {
		raw = 30 * time.Second
	}
	low := raw / 2
	return low + time.Duration(random()*float64(raw-low))
}

func sleepContext(ctx context.Context, delay time.Duration) bool {
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

type websocketConn struct {
	conn *websocket.Conn
}

func dialWebSocket(ctx context.Context, rawURL string) (*websocketConn, error) {
	dialer := *websocket.DefaultDialer
	dialer.HandshakeTimeout = 10 * time.Second
	conn, response, err := dialer.DialContext(ctx, rawURL, nil)
	if response != nil && response.Body != nil {
		_ = response.Body.Close()
	}
	if err != nil {
		return nil, err
	}

	stream := &websocketConn{conn: conn}
	conn.SetReadLimit(websocketMessageLimit)
	_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	})
	conn.SetPingHandler(func(data string) error {
		_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return conn.WriteControl(websocket.PongMessage, []byte(data), time.Now().Add(5*time.Second))
	})
	return stream, nil
}

func (s *websocketConn) readMessage() ([]byte, error) {
	_ = s.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	_, data, err := s.conn.ReadMessage()
	return data, err
}

func (s *websocketConn) writeJSON(value any) error {
	_ = s.conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	return s.conn.WriteJSON(value)
}

func (s *websocketConn) pingControl() error {
	return s.conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(5*time.Second))
}

func (s *websocketConn) Close() error {
	_ = s.conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""), time.Now().Add(time.Second))
	return s.conn.Close()
}

func fetchJSON(ctx context.Context, client *http.Client, rawURL string, target any) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return err
	}
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("upstream returned %s", response.Status)
	}

	data, err := io.ReadAll(io.LimitReader(response.Body, catalogBodyLimit+1))
	if err != nil {
		return err
	}
	if len(data) > catalogBodyLimit {
		return fmt.Errorf("catalog response exceeds %d bytes", catalogBodyLimit)
	}
	if err := json.Unmarshal(data, target); err != nil {
		return fmt.Errorf("decode catalog: %w", err)
	}
	return nil
}
