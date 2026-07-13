# Beacon Quote Relay Design

## Summary

Beacon Quote Relay is a single-user, self-hosted Go service that keeps persistent public market-data WebSocket connections and serves normalized quotes to the Beacon Raycast extension through one short authenticated HTTP request.

The first version runs as one Docker container inside `beacon/relay/`. It supports Bybit linear perpetuals, Binance USDⓈ-M futures, and Binance spot, in configurable priority order. It uses only in-memory state and does not require a database, Redis, message queue, OAuth, management UI, or exchange API keys.

This ticket delivers the relay, tests, Docker image, and deployment documentation. It does not modify the Raycast client.

## Scope

Included:

- One Go 1.24 service and Docker image.
- Static provider adapter registry.
- `bybit-linear`, `binance-futures`, and `binance-spot` adapters.
- One WebSocket connection per enabled source.
- Incremental subscriptions and automatic resubscription after reconnect.
- In-memory catalogs, subscription state, and latest quotes.
- Bearer-secret authentication and in-memory rate limiting.
- `/v1/quotes` and `/healthz` HTTP endpoints.
- Structured operational logs.
- Automated tests and a local live Docker smoke test.

Excluded:

- Raycast relay preferences or client integration.
- Runtime-loaded plugins.
- Databases or persistent quote caches.
- Multi-user authentication, OAuth, token refresh, or account management.
- Historical candles, alert evaluation, billing, admin UI, or high availability.
- Automatic aliases or multiplier normalization such as mapping `BONK` to `1000BONKUSDT`.
- A Prometheus metrics endpoint.

## Repository and Runtime

The service lives in `beacon/relay/` as an independent Go module. It does not share the Raycast extension's npm dependencies or build lifecycle.

Production runs one non-root Docker container. The service listens on plain HTTP; a hosting platform or trusted reverse proxy must terminate TLS. The README will recommend a starting limit of 0.5 CPU and 128 MiB memory.

## Architecture

The process contains four responsibilities:

1. **HTTP server** — authenticates, rate-limits, validates, and serves quote requests.
2. **Hub** — owns requested symbols and normalized in-memory quotes, coordinates subscriptions, waits for first snapshots, and selects the best source per symbol.
3. **Source runner** — owns one source connection, connection state, serialized writes, ping/pong, reconnect backoff, catalog refresh, incremental subscriptions, and full resubscription after reconnect.
4. **Adapters** — implement exchange-specific catalog loading, subscription messages, and ticker parsing.

Enabled sources are selected from a compile-time adapter registry. `SOURCES` supplies comma-separated adapter IDs in priority order. The default is:

```text
bybit-linear,binance-futures,binance-spot
```

Adding another exchange requires a new Go adapter and image rebuild. Runtime plugin loading is intentionally excluded.

## Source Connections and Catalogs

Each enabled source uses at most one WebSocket connection regardless of symbol count.

At startup, each adapter loads its market catalog through the exchange's public REST metadata endpoint. Catalog loading retries with backoff when unavailable and does not prevent the process or `/healthz` from starting. Successfully loaded catalogs refresh every six hours. A failed refresh preserves the last successful catalog.

Catalog filters are:

- Bybit: active USDT linear contracts.
- Binance futures: trading USDⓈ-M USDT contracts.
- Binance spot: trading USDT pairs.

A client symbol maps only to the exact upstream name `{SYMBOL}USDT`. A symbol is subscribable when at least one loaded catalog contains that exact name. Unknown symbols do not consume the instance subscription limit.

The Hub tracks whether each enabled source has completed at least one catalog load. A symbol absent from all catalogs is considered definitively unknown only when every enabled source has a ready catalog. If one or more initial catalog loads are still unavailable, the symbol is unresolved rather than unknown: it is not retained or subscribed, and a request with no other usable quote returns `503` instead of falsely reporting that the market does not exist. The next client request re-evaluates it after catalogs recover.

## Subscription Lifecycle

The Hub retains requested symbols for the process lifetime. It does not unsubscribe or apply a TTL.

For each newly accepted symbol, the Hub asks every enabled source whose catalog supports the symbol to subscribe. Subscription writes are serialized and batched to remain inside upstream message and control-rate limits.

The instance supports at most 100 distinct accepted client symbols. A request that would exceed the limit fails transactionally with `400`; none of its new symbols are added or subscribed.

After a source reconnects, its runner resubscribes the complete current set supported by that source.

## Reconnection

Unexpected disconnects use exponential equal-jitter delays:

```text
1–2s, 2–4s, 4–8s, 8–16s, 15–30s
```

The delay never drops below one second or exceeds 30 seconds. A connection must remain stable for 30 seconds before its retry attempt resets. This prevents repeated short-lived connections from creating a tight retry loop.

Each adapter implements the exchange's required ping/pong behavior. Binance's expected connection lifetime is treated as a normal reconnect and follows the same resubscription path.

## In-Memory Quote Model

The Hub stores the canonical latest values by normalized symbol and source:

```text
quotes[symbol][source] = {
  price,
  high24h,
  low24h,
  updatedAt
}
```

`updatedAt` is the relay's Unix-millisecond receipt time. Using relay time makes freshness comparable across exchanges and avoids relying on upstream clock skew.

The Hub does not maintain a duplicate preselected `bestQuotes` cache. Each HTTP request scans at most three source records per requested symbol, which is bounded by 50 requested symbols and avoids derived-cache invalidation when time passes or a connection changes state.

All public prices must be finite and positive. A quote becomes externally usable only after `price`, `high24h`, and `low24h` are valid. Invalid messages are discarded and never overwrite the previous valid state.

Bybit snapshot messages establish state. Delta messages update only fields present in the payload and retain unchanged values. Binance ticker messages update the corresponding futures or spot source state.

## Source Selection and Freshness

For each requested symbol, the Hub selects a quote in two passes:

1. Scan `SOURCES` in order and return the first quote whose source is connected and whose age is at most 30 seconds.
2. If no fresh quote exists, scan the same order and return the first cached quote whose age is at most 120 seconds, marked `stale: true`.

A disconnected source cannot produce a fresh quote even if its last update is recent. Quotes older than 120 seconds are never returned.

This means a lower-priority live source wins over a higher-priority stale source. A stale higher-priority source is used only when no source has a fresh quote.

## HTTP API

### Quotes

```http
GET /v1/quotes?symbols=BTC,ETH,SOL
Authorization: Bearer <secret>
```

Input behavior:

- `symbols` is required.
- Split on commas, uppercase, and deduplicate.
- Each symbol must match `[A-Z0-9]{2,20}`.
- Each request may contain 1–50 unique symbols.
- Only exact `{SYMBOL}USDT` catalog matches are subscribed.

New subscriptions wait up to two seconds for initial data. The wait ends when every accepted requested symbol has at least one usable source quote, the deadline expires, or the client disconnects. Warm-cache requests return immediately.

Successful response:

```json
{
  "serverTime": 1783900000000,
  "quotes": {
    "BTC": {
      "price": 62000.1,
      "high24h": 63000,
      "low24h": 60000,
      "source": "bybit-linear",
      "updatedAt": 1783899999000,
      "stale": false
    }
  },
  "missingSymbols": ["UNKNOWN"]
}
```

The response uses `Content-Type: application/json; charset=utf-8` and includes only requested symbols. Source selection and fallback are entirely server-side; the Raycast client does not need exchange-specific logic.

Status behavior:

- `200`: complete response, partial response, or all requested symbols are definitively unknown after every enabled catalog is ready.
- `400`: missing symbols, invalid format, over 50 request symbols, or over 100 instance symbols.
- `401`: missing or invalid Bearer secret.
- `405`: unsupported HTTP method.
- `429`: rate limit exceeded; include `Retry-After`.
- `503`: no requested quote is usable and at least one symbol is known-but-unavailable or unresolved because an initial source catalog is unavailable.
- `500`: unexpected server failure.

Errors use a stable envelope:

```json
{
  "error": {
    "code": "invalid_symbols",
    "message": "symbols must match [A-Z0-9]{2,20}"
  }
}
```

### Health

```http
GET /healthz
```

Response:

```json
{"status":"ok"}
```

`/healthz` is unauthenticated liveness only. It never includes quotes, secrets, configuration, catalogs, or upstream status.

## Authentication

`RELAY_TOKEN` is required and must contain at least 16 characters. The README recommends generating it with:

```bash
openssl rand -hex 32
```

The API accepts the secret only through `Authorization: Bearer`. Query-string tokens and custom token headers are not supported.

At startup the service hashes the configured token with SHA-256. Each presented token is also hashed, and the fixed-length digests are compared with Go's `subtle.ConstantTimeCompare`. Authorization headers and token values are never logged.

## Rate Limiting

`/v1/quotes` uses in-memory token buckets with a refill rate of 10 requests per minute and burst capacity of three:

- Every request first consumes from a bucket keyed by TCP peer IP, including invalid authentication attempts.
- Authenticated requests also consume from the single configured token bucket.

IP buckets idle for ten minutes are deleted to prevent unbounded memory growth. `/healthz` bypasses business authentication and rate limiting.

The first version uses the TCP peer address and does not trust `X-Forwarded-For`. Behind a reverse proxy this may make all traffic share one IP bucket, which is acceptable for the intended single user and normal load of about two requests per minute. Trusted-proxy parsing can be added if the service becomes multi-user.

## Limits and Timeouts

- Initial quote wait: 2 seconds.
- Total quote handler timeout: 2.5 seconds.
- HTTP header and request-line limit: 8 KiB.
- Generated response limit: 64 KiB.
- Upstream catalog response limit: 8 MiB.
- WebSocket message limit: 64 KiB.
- Instance accepted symbols: 100.
- Request symbols: 50.

Client cancellation immediately stops that request's wait. It does not roll back retained subscriptions or stop background source runners.

## Logging and Operations

The service writes structured JSON through Go `slog` to stdout.

Request logs contain only status, duration, and symbol count. They do not contain query values, authorization headers, tokens, or quote values.

Connection logs contain source ID, connect/disconnect events, reconnect count, and subscription count. Every 60 seconds the service logs, for each source:

- connected state;
- last-message age;
- subscription count;
- reconnect count;
- cumulative HTTP 5xx count.

No separate metrics server or Prometheus endpoint is included.

SIGTERM and SIGINT trigger graceful HTTP shutdown and WebSocket closure.

The service consumes only public market data and requires no exchange credentials. Deployment documentation must state that the service must run in a region where access is permitted and must not be used to bypass exchange geographic restrictions or terms.

## Testing

Automated tests use Go's standard `testing` and `httptest` packages plus local fake providers/WebSocket servers. They do not depend on public exchange availability.

Coverage includes:

- missing, invalid, and valid Bearer secrets;
- IP and token rate-limit burst/refill behavior;
- symbol normalization, deduplication, validation, and request/instance caps;
- unknown symbols not consuming the global cap;
- catalog pagination, filtering, failed-refresh preservation, and unresolved-symbol behavior before initial catalogs are ready;
- Bybit snapshot/delta merging;
- Binance futures and spot ticker parsing;
- fresh-first priority selection and spot fallback;
- 30-second stale transition and 120-second expiration;
- partial `200`, unknown-only `200`, and upstream-unavailable `503` responses;
- JSON content type and stable response/error shapes;
- one Bybit connection serving at least 20 subscriptions without REST ticker requests;
- reconnect jitter bounds and no tight retry loop;
- resubscription of the complete set after reconnect;
- oversized messages, invalid JSON, and invalid prices preserving the last valid quote.

Required checks:

```bash
go test ./...
go test -race ./...
go vet ./...
docker build .
```

## Local Live Smoke Test

After automated checks, build and run the container locally with a generated token. Verify:

- `/healthz` succeeds;
- `/v1/quotes` without a token returns `401`;
- an authenticated request for 20 symbols returns quotes or explicit missing symbols;
- logs show at most one connection per enabled source;
- a repeated warm-cache request does not wait for another snapshot;
- Binance futures or spot supplies quotes if Bybit is unavailable in the current region.

The live smoke test remains a documented/manual verification because public exchange access is network- and region-dependent.

## Minimal File Layout

```text
relay/
├── go.mod
├── main.go
├── config.go
├── server.go
├── hub.go
├── source.go
├── bybit.go
├── binance.go
├── *_test.go
├── Dockerfile
├── .dockerignore
└── README.md
```

All Go files remain in one package. No Web framework or separate `internal/` hierarchy is introduced. The only planned third-party dependency is a WebSocket library.

## Documentation

`relay/README.md` will document:

- Docker build and run commands;
- `RELAY_TOKEN`, `SOURCES`, and listen-address configuration;
- CPU and memory recommendations;
- HTTPS termination requirements;
- authenticated curl examples;
- response and error formats;
- local live verification;
- future Raycast fields: relay URL and password-style relay token preference.

## Acceptance Criteria

- Twenty symbols use one Bybit WebSocket connection and no per-symbol REST ticker requests.
- Enabled sources each use at most one WebSocket connection.
- Hot-cache responses contain only requested symbols and are suitable for a deployment-region p95 target below 200 ms.
- Invalid auth returns `401`, rate limits return `429`, and invalid or excessive symbols return `400`.
- Reconnects are delayed, jittered, and restore subscriptions.
- Lower-priority fresh quotes beat higher-priority stale quotes.
- Quotes older than 120 seconds are never presented as current.
- Automated tests cover authentication, validation, parsing/merging, priority, stale rules, and reconnect behavior.
- Dockerized local live verification reaches the relay successfully.
- README documents deployment, environment variables, curl usage, and later Raycast integration fields.
