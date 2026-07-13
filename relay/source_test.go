package main

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"testing"
	"time"
)

func TestBackoffDelayBounds(t *testing.T) {
	bounds := [][2]time.Duration{
		{time.Second, 2 * time.Second},
		{2 * time.Second, 4 * time.Second},
		{4 * time.Second, 8 * time.Second},
		{8 * time.Second, 16 * time.Second},
		{15 * time.Second, 30 * time.Second},
	}
	for attempt, bound := range bounds {
		if got := backoffDelay(attempt, func() float64 { return 0 }); got != bound[0] {
			t.Fatalf("attempt %d low=%s, want %s", attempt, got, bound[0])
		}
		if got := backoffDelay(attempt, func() float64 { return 0.999999 }); got < bound[0] || got >= bound[1] {
			t.Fatalf("attempt %d high=%s, want [%s,%s)", attempt, got, bound[0], bound[1])
		}
	}
}

func TestRunnerSubscribesTwentySymbolsAndResubscribes(t *testing.T) {
	h := newHub([]string{"fake"}, time.Now)
	runner := newSourceRunner(fakeAdapter{id: "fake"}, h, slog.New(slog.NewTextHandler(io.Discard, nil)))
	symbols := make([]string, 20)
	for i := range symbols {
		symbols[i] = string(rune('A' + i))
	}
	runner.AddSubscriptions(symbols)

	first := newFakeStream()
	runUntilSubscribed(t, runner, first, 20)
	second := newFakeStream()
	runUntilSubscribed(t, runner, second, 20)
}

func runUntilSubscribed(t *testing.T, runner *sourceRunner, stream *fakeStream, want int) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- runner.runConnection(ctx, stream) }()

	select {
	case symbols := <-stream.subscribed:
		if len(symbols) != want {
			t.Fatalf("subscribed=%d, want %d", len(symbols), want)
		}
	case <-time.After(time.Second):
		t.Fatal("subscription timed out")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("runner did not stop")
	}
}

type fakeAdapter struct{ id string }

func (a fakeAdapter) ID() string { return a.id }
func (a fakeAdapter) LoadCatalog(context.Context) (map[string]struct{}, error) {
	return nil, errors.New("unused")
}
func (a fakeAdapter) Dial(context.Context) (sourceStream, error) {
	return nil, errors.New("unused")
}

type fakeStream struct {
	subscribed chan []string
	reads      chan fakeRead
	closed     chan struct{}
	closeOnce  sync.Once
}

type fakeRead struct {
	update *quoteUpdate
	err    error
}

func newFakeStream() *fakeStream {
	return &fakeStream{
		subscribed: make(chan []string, 4),
		reads:      make(chan fakeRead),
		closed:     make(chan struct{}),
	}
}

func (s *fakeStream) Subscribe(symbols []string) error {
	copyOfSymbols := append([]string(nil), symbols...)
	s.subscribed <- copyOfSymbols
	return nil
}
func (s *fakeStream) Ping() error { return nil }
func (s *fakeStream) Read() (*quoteUpdate, error) {
	select {
	case result := <-s.reads:
		return result.update, result.err
	case <-s.closed:
		return nil, io.EOF
	}
}
func (s *fakeStream) Close() error {
	s.closeOnce.Do(func() { close(s.closed) })
	return nil
}
