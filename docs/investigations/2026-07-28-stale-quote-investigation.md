# Beacon stale quote investigation and correction

Date: 2026-07-28

## Scope and baseline

- Parent workspace commit: `dd2592a3209e7d3a3c000e2ab4ff50fe94c79de0`
- Beacon commit: `1d83c0064c864e6cd4f188ebf5fecb2a73aec322` (detached HEAD)
- The five pre-existing client edits were preserved throughout. Their baseline and final diff SHA-256 is `488dedf48349e54900ab495c3f551a605c39ddce787e289a5306b039d250c895`.
- Source package sent for external review:
  - path: `/private/tmp/beacon-stale-status-dd2592a-1d83c006-20260728.zip`
  - size: `221166` bytes
  - SHA-256: `7beafee87d85a4dca47a96a7768339985b031a86977b9393d9acc84cddfa3c9c`
  - 74 files; `unzip -t` passed.
  - `.git`, dependencies, build output, caches, databases, runtime/browser state, `.env` files, credentials, tokens, keys, and cookies were excluded.
  - filename, credential-pattern, private-key, and high-entropy scans found no credential material.
- ChatGPT Pro review conversation: <https://chatgpt.com/c/6a6908e4-ef64-83ed-b6e2-d4ccbb92ebc5>

The pre-change repository gates passed: 18 Jest suites/133 tests, Raycast lint, Raycast production build, `go test ./...`, `go test -race ./...`, and `go vet ./...`.

## Findings

The menu status is downstream of relay freshness; the client was correctly displaying `stale: true`. The primary defects were in the relay ingestion and cache semantics.

### 1. Valid Bybit deltas were discarded

Bybit V5 derivatives tickers use snapshot/delta semantics. A field omitted from a delta is unchanged. The old parser returned `nil` when a valid symbol delta omitted all three fields retained by Beacon (`lastPrice`, `highPrice24h`, and `lowPrice24h`). Consequently, the per-symbol receipt time stopped advancing even while the connection and source-level message clock were healthy.

This was reproduced before the fix with public market data: QQQ became stale after roughly 48 seconds while the Bybit source remained connected, its `last_message_age_ms` was effectively zero, subscriptions were intact, and reconnects remained zero.

Official reference: <https://bybit-exchange.github.io/docs/v5/websocket/public/ticker>

### 2. Binance Futures fallback used a retired route

The relay connected to the legacy unrouted `wss://fstream.binance.com/ws`. Binance now routes regular ticker data through `/market`; legacy unrouted market streams stopped pushing after 2026-04-23. The relay therefore lost the futures fallback that should cover a stale higher-priority Bybit quote.

The corrected endpoint is `wss://fstream.binance.com/market/stream`, with combined-payload unwrapping.

Official references:

- <https://developers.binance.com/en/docs/products/derivatives-trading-usds-futures/websocket-market-streams/Connect>
- <https://developers.binance.com/en/docs/products/derivatives-trading-usds-futures/websocket-market-streams/Important-WebSocket-Change-Notice>

### 3. Real Binance compact payloads triggered Go JSON key collisions

ChatGPT Pro's first patch corrected the route but still returned HTTP 503 in an independent live smoke test. The source was connected and receiving messages every few seconds.

A real combined payload contains compact lowercase fields and uppercase timestamp/ID fields in the same object, notably `e`/`E`, `c`/`C`, and `l`/`L`. Go's `encoding/json` struct-field matching is case-insensitive when an exact alternative is absent. The old struct decoding allowed later uppercase values to overwrite lowercase fields:

- numeric `E` replaced string event type `e`, causing the parser to return `nil`;
- after correcting that field alone, numeric `C` attempted to overwrite string close price `c`, causing reconnect loops;
- `l`/`L` had the same latent collision.

The final parser unwraps combined events, then reads every consumed compact key from a `map[string]json.RawMessage` by exact key. Regression fixtures contain the realistic uppercase collision fields for both raw and combined payloads.

### 4. Reconnects could temporarily re-fresh old state

The cache had no connection identity. After a reconnect, a retained pre-reconnect record could appear fresh as soon as the source became connected, before the new connection had established complete state for that symbol.

The fix assigns each source connection a generation. Fresh selection now requires complete state established on the current generation. A partial post-reconnect delta cannot modify, refresh, or extend the retained pre-reconnect cache; a complete current-generation state restores freshness.

## Implemented changes

Only six relay files implement the product fix:

- `relay/README.md`
- `relay/adapters_test.go`
- `relay/binance.go`
- `relay/bybit.go`
- `relay/hub.go`
- `relay/hub_test.go`

The behavior is now:

1. A complete ticker snapshot establishes tracked state for the current connection.
2. A valid current-generation Bybit delta may retain omitted tracked values while advancing the per-symbol observation time.
3. Transport liveness never refreshes every cached symbol.
4. Disconnected or pre-generation cache is stale immediately, remains bounded by the existing 120-second maximum, and cannot suppress a fresh lower-priority source.
5. The existing 30-second fresh threshold and 120-second maximum age are unchanged.
6. Binance Futures uses the routed market endpoint and exact compact-key parsing.

No dependencies or lock files changed. No credentials, per-symbol REST fallback, client direct-exchange fallback, API shape change, database change, or production configuration change was introduced.

## External review correction loop

The verified first ChatGPT Pro artifacts were:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `beacon-stale-investigation-report.md` | 21433 bytes | `461171c0b7464700949c7f356f74f68df008373de111e006dbe2928123496ffc` |
| `beacon-stale-fix.patch` | 14203 bytes | `75205fcc1bf32af92c912c0d4addd2193c255dc18386c798c62d189241b65d51` |
| `beacon-stale-status-fixed-20260728.zip` | 223369 bytes | `22ffb380149b48c4af6aa88d5518846baa0e5e0e598f5ded791e5fe93c735f1c` |
| `beacon-stale-verification-logs.zip` | 6215 bytes | `72975f6f31f577ca67674b1f3b54b0150e9d653179f64bc9662ac8efe9bec679` |

Both ZIP integrity checks passed. The first patch's six changed files matched its revised archive, and the five pre-existing client edits remained byte-for-byte unchanged.

The first patch was rejected after the live Binance test exposed the `e`/`E`, `c`/`C`, and `l`/`L` collisions. Exact raw payload evidence, HTTP 503 logs, source status, and the required realistic fixtures were sent back to ChatGPT Pro for correction.

The replacement v2 artifacts supersede every v1 artifact:

| Artifact | Size | SHA-256 |
| --- | ---: | --- |
| `beacon-stale-investigation-report-v2.md` | 21690 bytes | `c7588ce6bbf37abecf7fe4e1a4a461d9b47471bb413a3db28921d85ac5ff2e5c` |
| `beacon-stale-fix-v2.patch` | 19209 bytes | `6f578467ab18231919d35675c0bef4d9fd68d40d35e272016567ac37c3cad041` |
| `beacon-stale-status-fixed-v2-20260728.zip` | 219588 bytes | `2705eb0dc2d0a62254622a42052b97054041c7be966dc06d5824dd1541e3a7ac` |
| `beacon-stale-verification-logs-v2.zip` | 12997 bytes | `7f54acf9580277459545b1d32534303db1a46b9fda6a56b5bb1d2921f7c967cb` |

All four downloaded sizes and hashes matched the v2 claims, and both ZIP integrity checks passed. The complete v2 patch was dry-run and applied to a second fresh isolated worktree at `/private/tmp/beacon-stale-v2-validation-20260728`. Every packaged file matched the v2 source archive, the six-file scope was preserved, and the five pre-existing client edits retained the same baseline hash. The v2 implementation additionally uses exact key lookup for the combined `stream`/`data` envelope and tests malformed or case-mismatched envelope keys; this stricter implementation was selected for the final working tree.

## Independent validation

### Final repository gates

All were run from the actual working tree after the final local changes:

- `npm test -- --runInBand`: PASS — 18/18 suites, 133/133 tests.
- `npm run lint`: PASS — package/schema validation, icons, ESLint, and Prettier.
- `RAY_Target=x npm run build`: PASS — compiled, generated types, TypeScript checked, production build completed.
- `go test ./...`: PASS.
- `go test -race ./...`: PASS.
- `go vet ./...`: PASS.
- `gofmt -d` on the changed Go files: no output.

The same functional patch was first applied and tested in the isolated worktree `/private/tmp/beacon-stale-validation-20260728`. The actual six relay files were compared against that worktree after application and were identical.

The replacement v2 patch was then independently repeated in `/private/tmp/beacon-stale-v2-validation-20260728`. All final repository gates listed above passed there and again in the actual working tree after the exact v2 `binance.go` and `adapters_test.go` were synchronized.

Docker client version 29.4.0 was present, but the local Docker/OrbStack daemon socket was unavailable. `docker build` was therefore not executed and is not claimed.

### Public live smoke tests

These tests used only public exchange data, a dummy local relay token, and loopback HTTP. They were not production or staging validation.

Before the final Binance parser correction:

- routed endpoint connected and received combined messages;
- BTC request returned HTTP 503 with `quotes:{}` and `missingSymbols:["BTC"]`;
- source status showed `connected:true`, `catalog_ready:true`, subscription count 1, reconnect count 0, and last-message age around 1.8 seconds;
- exact payload parsing proved the lowercase/uppercase key collisions.

After the final correction:

- Binance Futures-only relay returned HTTP 200 with a BTC quote from `binance-futures`, `stale:false`, and no missing symbols.
- The exact v2 parser was separately re-run against Binance Futures public data and again returned HTTP 200 with `stale:false` and no missing symbols.
- Bybit-only QQQ initial observation:
  - price `677.4`
  - `updatedAt: 1785272028594`
  - `stale:false`
- More than 30 seconds later, with price/high/low unchanged:
  - price `677.4`
  - `updatedAt: 1785272076689` (advanced by 48095 ms)
  - `stale:false`
  - no missing symbols
- Simultaneous Bybit source status: connected, catalog ready, last-message age 103 ms, two subscriptions, zero reconnects, zero HTTP 5xx responses.

## Remaining risks and status

- No production relay logs, actual affected-symbol list, production network path, regional routing, proxy/firewall behavior, process restart behavior, exchange incident data, or Raycast production refresh telemetry was available.
- The public live tests demonstrate exchange compatibility from this machine at one point in time; they do not prove production availability or latency.
- Docker image construction remains unverified because no daemon was available.
- No Git commit, push, pull request, deployment, database migration, production configuration change, production feature enablement, or real-user-data operation was performed.
- The result is local working-tree changes only.
