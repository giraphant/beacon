package main

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	maxRequestSymbols = 50
	responseBodyLimit = 64 << 10
	handlerTimeout    = 2500 * time.Millisecond
	initialQuoteWait  = 2 * time.Second
)

var symbolPattern = regexp.MustCompile(`^[A-Z0-9]{2,20}$`)

type quoteResponse struct {
	ServerTime     int64                    `json:"serverTime"`
	Quotes         map[string]selectedQuote `json:"quotes"`
	MissingSymbols []string                 `json:"missingSymbols"`
}

type errorBody struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

type apiServer struct {
	hub            *hub
	subscribers    map[string]func([]string)
	tokenHash      [sha256.Size]byte
	ipLimiter      *rateLimiter
	tokenLimiter   *rateLimiter
	logger         *slog.Logger
	now            func() time.Time
	handlerTimeout time.Duration
	quoteWait      time.Duration
	http5xx        atomic.Uint64
}

func newAPIServer(hub *hub, subscribers map[string]func([]string), tokenHash [sha256.Size]byte, logger *slog.Logger) *apiServer {
	return &apiServer{
		hub:            hub,
		subscribers:    subscribers,
		tokenHash:      tokenHash,
		ipLimiter:      newRateLimiter(10, time.Minute, 3, 10*time.Minute),
		tokenLimiter:   newRateLimiter(10, time.Minute, 3, 10*time.Minute),
		logger:         logger,
		now:            time.Now,
		handlerTimeout: handlerTimeout,
		quoteWait:      initialQuoteWait,
	}
}

func (s *apiServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	started := s.now()
	status := http.StatusNotFound
	symbolCount := 0

	switch r.URL.Path {
	case "/healthz":
		status = s.handleHealth(w, r)
	case "/v1/quotes":
		status, symbolCount = s.handleQuotes(w, r)
	default:
		status = s.writeError(w, http.StatusNotFound, "not_found", "endpoint not found")
	}

	if status >= 500 {
		s.http5xx.Add(1)
	}
	s.logger.Info("http request",
		"method", r.Method,
		"path", r.URL.Path,
		"status", status,
		"duration_ms", s.now().Sub(started).Milliseconds(),
		"symbol_count", symbolCount,
	)
}

func (s *apiServer) handleHealth(w http.ResponseWriter, r *http.Request) int {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		return s.writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "only GET is allowed")
	}
	return s.writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *apiServer) handleQuotes(w http.ResponseWriter, r *http.Request) (int, int) {
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", http.MethodGet)
		return s.writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "only GET is allowed"), 0
	}

	now := s.now()
	if !s.ipLimiter.Allow(clientIP(r.RemoteAddr), now) {
		w.Header().Set("Retry-After", "6")
		return s.writeError(w, http.StatusTooManyRequests, "rate_limited", "too many requests"), 0
	}
	if !s.authorized(r.Header.Get("Authorization")) {
		return s.writeError(w, http.StatusUnauthorized, "unauthorized", "invalid bearer token"), 0
	}
	if !s.tokenLimiter.Allow("configured-token", now) {
		w.Header().Set("Retry-After", "6")
		return s.writeError(w, http.StatusTooManyRequests, "rate_limited", "too many requests"), 0
	}

	symbols, err := parseSymbols(r.URL.Query().Get("symbols"))
	if err != nil {
		return s.writeError(w, http.StatusBadRequest, "invalid_symbols", err.Error()), 0
	}
	plan, err := s.hub.prepare(symbols)
	if errors.Is(err, errSymbolLimit) {
		return s.writeError(w, http.StatusBadRequest, "symbol_limit_exceeded", "instance supports at most 100 symbols"), len(symbols)
	}
	if err != nil {
		return s.writeError(w, http.StatusInternalServerError, "internal_error", "internal server error"), len(symbols)
	}

	for source, sourceSymbols := range plan.subscriptions {
		if subscribe := s.subscribers[source]; subscribe != nil {
			subscribe(sourceSymbols)
		}
	}

	handlerCtx, cancelHandler := contextWithTimeout(r, s.handlerTimeout)
	defer cancelHandler()
	waitCtx, cancelWait := contextWithTimeoutFrom(handlerCtx, s.quoteWait)
	s.hub.waitForQuotes(waitCtx, plan.known)
	cancelWait()

	quotes, missing := s.hub.selectQuotes(symbols)
	status := http.StatusOK
	if len(quotes) == 0 && (len(plan.known) > 0 || len(plan.unresolved) > 0) {
		status = http.StatusServiceUnavailable
	}
	response := quoteResponse{
		ServerTime:     s.now().UnixMilli(),
		Quotes:         quotes,
		MissingSymbols: missing,
	}
	return s.writeJSON(w, status, response), len(symbols)
}

func (s *apiServer) authorized(header string) bool {
	scheme, secret, ok := strings.Cut(strings.TrimSpace(header), " ")
	if !ok || !strings.EqualFold(scheme, "Bearer") || secret == "" {
		return false
	}
	presented := sha256.Sum256([]byte(secret))
	return subtle.ConstantTimeCompare(presented[:], s.tokenHash[:]) == 1
}

func (s *apiServer) writeError(w http.ResponseWriter, status int, code, message string) int {
	body := errorBody{}
	body.Error.Code = code
	body.Error.Message = message
	return s.writeJSON(w, status, body)
}

func (s *apiServer) writeJSON(w http.ResponseWriter, status int, body any) int {
	data, err := json.Marshal(body)
	if err != nil || len(data) > responseBodyLimit {
		status = http.StatusInternalServerError
		data = []byte(`{"error":{"code":"internal_error","message":"internal server error"}}`)
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write(append(data, '\n'))
	return status
}

func parseSymbols(raw string) ([]string, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, errors.New("symbols is required")
	}

	seen := make(map[string]struct{})
	symbols := make([]string, 0)
	for _, part := range strings.Split(raw, ",") {
		symbol := strings.ToUpper(strings.TrimSpace(part))
		if !symbolPattern.MatchString(symbol) {
			return nil, errors.New("symbols must match [A-Z0-9]{2,20}")
		}
		if _, duplicate := seen[symbol]; duplicate {
			continue
		}
		seen[symbol] = struct{}{}
		symbols = append(symbols, symbol)
		if len(symbols) > maxRequestSymbols {
			return nil, errors.New("at most 50 symbols are allowed")
		}
	}
	return symbols, nil
}

func clientIP(remoteAddr string) string {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err == nil {
		return host
	}
	return remoteAddr
}

type rateBucket struct {
	tokens   float64
	last     time.Time
	lastSeen time.Time
}

type rateLimiter struct {
	mu          sync.Mutex
	buckets     map[string]*rateBucket
	refillRate  float64
	burst       float64
	idleTTL     time.Duration
	lastCleanup time.Time
}

func newRateLimiter(requests int, per time.Duration, burst int, idleTTL time.Duration) *rateLimiter {
	return &rateLimiter{
		buckets:    make(map[string]*rateBucket),
		refillRate: float64(requests) / per.Seconds(),
		burst:      float64(burst),
		idleTTL:    idleTTL,
	}
}

func (l *rateLimiter) Allow(key string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.lastCleanup.IsZero() || now.Sub(l.lastCleanup) >= time.Minute {
		for bucketKey, bucket := range l.buckets {
			if now.Sub(bucket.lastSeen) > l.idleTTL {
				delete(l.buckets, bucketKey)
			}
		}
		l.lastCleanup = now
	}

	bucket := l.buckets[key]
	if bucket == nil {
		bucket = &rateBucket{tokens: l.burst, last: now, lastSeen: now}
		l.buckets[key] = bucket
	}
	elapsed := now.Sub(bucket.last).Seconds()
	if elapsed > 0 {
		bucket.tokens = min(l.burst, bucket.tokens+elapsed*l.refillRate)
		bucket.last = now
	}
	bucket.lastSeen = now
	if bucket.tokens < 1 {
		return false
	}
	bucket.tokens--
	return true
}

func contextWithTimeout(r *http.Request, timeout time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(r.Context(), timeout)
}

func contextWithTimeoutFrom(parent context.Context, timeout time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, timeout)
}
