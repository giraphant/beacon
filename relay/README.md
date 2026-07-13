# Beacon Quote Relay

A single-user HTTP relay for Beacon. It keeps public market-data WebSocket connections open, stores the latest normalized quotes in memory, and returns requested symbols through one authenticated request.

Enabled by default, in priority order:

1. `bybit-linear`
2. `binance-futures`
3. `binance-spot`

The relay prefers a fresh quote from any higher-priority source, then falls back to a lower-priority fresh quote. Only when no fresh quote exists does it return cache data up to 120 seconds old with `stale: true`.

## Requirements

- Docker, or Go 1.24+
- A deployment region where the configured exchanges permit access
- HTTPS termination from the hosting platform, Caddy, or Nginx

The relay consumes public market data and does not need exchange API keys. Do not use it to bypass exchange geographic restrictions or terms.

## Configuration

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `RELAY_TOKEN` | yes | — | Static Bearer secret, at least 16 characters |
| `SOURCES` | no | `bybit-linear,binance-futures,binance-spot` | Enabled source IDs in priority order |
| `LISTEN_ADDR` | no | `:18765` | HTTP listen address |

Generate a secret:

```bash
export RELAY_TOKEN="$(openssl rand -hex 32)"
```

## Run with Docker

From this directory:

```bash
docker build -t beacon-relay .
docker run --rm \
  --name beacon-relay \
  --cpus 0.5 \
  --memory 128m \
  -p 18765:18765 \
  -e RELAY_TOKEN \
  -e SOURCES=bybit-linear,binance-futures,binance-spot \
  beacon-relay
```

The container runs as a non-root user and serves plain HTTP on port 18765. Put it behind HTTPS before exposing it outside the local machine.

## Paste directly into Coolify

`Dockerfile.coolify` is standalone: it clones the public Beacon repository and builds the relay without requiring repository files in the Docker build context. Copy that file verbatim into a Dockerfile-based Coolify resource, set `RELAY_TOKEN`, expose container port `18765`, and attach an HTTPS domain.

The optional `BEACON_REF` build argument defaults to `main` and may be set to a branch or tag. The image includes a `/healthz` Docker health check.

## Run from source

```bash
RELAY_TOKEN="$RELAY_TOKEN" go run .
```

## API

### Health

No authentication is required:

```bash
curl -i http://127.0.0.1:18765/healthz
```

```json
{"status":"ok"}
```

This endpoint is liveness-only and does not expose upstream state, quotes, or configuration.

### Quotes

```bash
curl --fail-with-body \
  -H "Authorization: Bearer $RELAY_TOKEN" \
  "http://127.0.0.1:18765/v1/quotes?symbols=BTC,ETH,SOL"
```

Example response:

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

Rules:

- Symbols are uppercased and deduplicated.
- Each symbol must match `[A-Z0-9]{2,20}`.
- One request accepts at most 50 unique symbols.
- One process retains at most 100 valid symbols until restart.
- A client symbol maps only to an exact `{SYMBOL}USDT` market; multiplier aliases such as `1000BONKUSDT` are not inferred.
- New subscriptions wait up to two seconds for initial data. Warm-cache requests return immediately.
- The response contains only requested symbols.

Status codes:

- `200`: complete, partial, or definitively unknown symbols
- `400`: invalid input or symbol limits
- `401`: missing or invalid Bearer secret
- `405`: non-GET request
- `429`: 10 requests/minute, burst 3; inspect `Retry-After`
- `503`: known symbols have no usable cache, or catalogs are not ready to classify them

The token must be sent in `Authorization`. Query-string tokens are not accepted.

## Tests

```bash
go test ./...
go test -race ./...
go vet ./...
docker build -t beacon-relay .
```

Tests use local fakes and do not require public exchange access.

## Live smoke test

With the container running:

```bash
curl -i http://127.0.0.1:18765/healthz
curl -i "http://127.0.0.1:18765/v1/quotes?symbols=BTC"
curl --fail-with-body \
  -H "Authorization: Bearer $RELAY_TOKEN" \
  "http://127.0.0.1:18765/v1/quotes?symbols=BTC,ETH,SOL,XRP,DOGE,ADA,AVAX,LINK,DOT,LTC,BCH,UNI,ATOM,NEAR,APT,ARB,OP,FIL,ETC,AAVE"
```

The second command should return `401`. The authenticated request should return available quotes and explicit `missingSymbols`. Logs should show no more than one connection for each enabled source. Repeat the authenticated request to exercise the warm cache.

Public exchange connectivity is network- and region-dependent. A source may remain unavailable while another source supplies the quote.

## Operations

The process writes JSON logs to stdout. It records request status/duration/symbol count, source connection changes, catalog refreshes, reconnect count, subscription count, last-message age, and cumulative HTTP 5xx responses. It never logs authorization headers, secrets, requested symbol values, or quote values.

Catalogs refresh every six hours. Failed refreshes preserve the last successful catalog. WebSocket reconnect delay uses jittered exponential backoff from 1–2 seconds up to 15–30 seconds, then restores retained subscriptions.

All state is in memory. Restarting clears quotes and subscriptions; the next client request establishes them again.

## Future Raycast integration

The later Beacon client change needs two password/preferences fields:

- Relay URL, such as `https://relay.example.com`
- Relay token, stored as a Raycast password preference

The client should call `/v1/quotes` once per 30-second refresh with a three-second timeout and keep its existing local display cache when the relay is temporarily unavailable.
