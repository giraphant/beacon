# Beacon native quote diagnostics

Date: 2026-07-28

## Purpose and baseline

The active client was confirmed to be the native macOS application
`/Applications/Beacon.app` (`com.inol.beacon`), not the Raycast menu-bar
extension. This follow-up adds a bounded local trace so quote freshness can be
diagnosed without manually watching the menu.

- Beacon baseline and remote `main`:
  `b4af4e286552237d754ddad47cc054fdc8d60c6a`
- Relay correction commit:
  <https://github.com/giraphant/beacon/commit/b4af4e286552237d754ddad47cc054fdc8d60c6a>
- External engineering review:
  <https://chatgpt.com/c/6a6908e4-ef64-83ed-b6e2-d4ccbb92ebc5>
- Latest external-review source archive (created before the small Status
  timestamp correction described below):
  `/private/tmp/beacon-native-diagnostics-b4af4e2-v4-20260728.zip`
- Archive size: `302145` bytes
- Archive SHA-256:
  `d860b271e5ca8a69b7489eccdbcb2d267bb19241af1bd56834762d2d48cb83f9`
- Complete native patch size: `29190` bytes
- Complete native patch SHA-256:
  `83474e37dd779b109776ef6a56627142dc8f9723e40a82817d3a82f43e2f1e02`

The ZIP integrity check passed. It contains tracked source plus the two new
Swift files and excludes Git metadata, dependencies, build output, caches,
databases, runtime/browser state, environment files, credentials, keys, and
cookies. Credential-format scanning found no matches. A broader generic scan
found only two deliberately synthetic secret strings in the diagnostic tests;
both tests assert those strings never reach output.

The five pre-existing Raycast edits were preserved byte-for-byte throughout.
Their diff SHA-256 remains
`488dedf48349e54900ab495c3f551a605c39ddce787e289a5306b039d250c895`.

## Implementation

The native app now records these correlated JSONL events:

- `session_start`: diagnostic schema, app version, and build number
- `fetch_start`: request ID, selected source kind, and sanitized symbols
- `fetch_success`: duration, result time, missing symbols, normalized errors,
  and each requested quote's symbol, allowlisted upstream source, `updatedAt`,
  client age, and `stale`
- `fetch_failure`: request ID, duration, and a fixed error category/message
- `display_decision`: `live`, `cache_after_error`, or `error_only`, plus the
  sanitized quote state actually selected for display

The files are:

```text
~/Library/Logs/Beacon/quote-diagnostics.jsonl
~/Library/Logs/Beacon/quote-diagnostics.previous.jsonl
```

Each file is hard-bounded at 256 KiB. Rotation keeps only current and previous
files, and every new current file begins with a `session_start` marker. An
individual event that cannot fit the bound is dropped non-fatally.

`QuoteDiagnosticLogger` constructs and queues events. Ordered file work runs on
a separate `QuoteDiagnosticFileWriter` actor, so the app's refresh path does not
wait behind synchronous filesystem operations. Diagnostic failures are ignored
and cannot alter fetching, display, cache, or alert behavior.

Privacy is fail-closed:

- no quote values, highs, lows, relay URL, bearer token, Authorization header,
  keychain contents, preferences object, raw body, or arbitrary error text;
- symbols must match ASCII `[A-Z0-9]{2,20}` and returned/missing symbols must
  also have been requested;
- upstream sources are limited to the two native source labels and the three
  relay adapter IDs; unknown strings become `unknown`;
- errors map to fixed categories and fixed messages.

The existing one-request Relay behavior, source-signature cache reset, stale
quote visibility, and exclusion of stale quotes from both alert evaluators are
unchanged.

## Status timestamp correction

The native Status menu previously rendered `QuoteFetchResult.updatedAt`. For a
Relay response, that field is the relay's response `serverTime`, so every
successful refresh made the UI report `Updated: 0s ago` even when an individual
quote was several seconds old.

The Status menu now uses the oldest valid `updatedAt` among the displayed
quotes. This makes the single summary line conservative: one active symbol
cannot hide an older displayed quote. A regression test fixes the distinction
between response time and per-quote observation time.

## External review correction loop

The first external task incorrectly targeted the Raycast command. Process
inspection corrected the scope to the native app, and the Raycast diagnostic
proposal was rejected.

The native v1 review identified two release blockers:

1. an oversized first event could exceed the advertised file cap;
2. quote symbol/source strings needed a diagnostic allowlist.

Independent review also identified that file I/O should not share the logger
actor that the refresh path awaits. The final v4 implementation adds the hard
oversize guard, strict requested-symbol/source filtering, per-rotation session
markers, a separate writer actor, and focused regression tests. Passing a
`FileManager` instance across the actor boundary was then removed after an
additional Swift concurrency warning build.

## Independent validation

All commands below were run against the final working tree:

- Native `make test`: PASS — 119/119 tests.
- Native `make build`: PASS — release application built and ad-hoc signed.
- `swift build -Xswiftc -warn-concurrency`: PASS. No warning originates from
  `QuoteDiagnostics.swift`; remaining warnings are pre-existing Swift 6
  migration warnings in preferences, storage defaults, and alert closures.
- `npm test -- --runInBand`: PASS — 18/18 suites, 133/133 tests.
- `npm run lint`: PASS, including online Raycast package/schema validation.
- `npm run build`: PASS, including TypeScript checking.
- Relay `go test ./...`: PASS.
- Relay `go test -race ./...`: PASS.
- Relay `go vet ./...`: PASS.
- Relay `go build ./...`: PASS.
- Docker image build: NOT RUN; the installed Docker client could not reach the
  stopped local OrbStack daemon.

The final installed application is:

- path: `/Applications/Beacon.app`
- version: `1.0.1 (2)`
- binary size: `1736992` bytes
- binary SHA-256:
  `f45320f0777a0006e8e644015fa6ce1a11f49741618264875e9e04a4adbce65e`
- signature: valid ad-hoc signature; no Developer ID identity is installed

After the Status correction, the installed build started and completed four
real live refreshes of all 11 requested symbols with no failures, missing
symbols, or stale observations. In the first refresh its relay response was
about 0.2 seconds old while the oldest displayed quote was about 2.5 seconds
old, directly exercising the two timestamps that the UI previously conflated.

The immediately preceding equivalent diagnostic session ran four successful
live refreshes across roughly 70 seconds:

- 4 fetch starts, 4 successes, 0 failures
- 4 `live` display decisions, no cache-after-error display
- 0 stale observations
- every one of the 11 requested symbols advanced `updatedAt` by approximately
  69.6–72.7 seconds
- maximum observed per-symbol age was below 4.8 seconds

This is a real local native client calling the user's deployed relay and public
exchange data. It is not a production- or staging-environment validation. The
JSONL parsed successfully, remained within the bound, and contained no match
for Authorization, Bearer, URL, token, price, high, or low patterns.

## Interpretation and remaining risks

The trace supports the relay diagnosis: after the relay commit was rebuilt by
the user, even quiet/equity-like symbols continuously advanced their
observation times beyond the 30-second stale threshold. No client cache/render
divergence appeared in the captured interval.

Residual risks:

- the observation window does not prove long-term exchange or production
  availability;
- no forced failure was introduced against the user's live relay, so
  `cache_after_error` is unit-tested but was not induced in the live session;
- the first refresh after an ad-hoc-signed reinstall can spend substantially
  longer in keychain access; subsequent observed refreshes completed in roughly
  0.5 seconds;
- ad-hoc signing may cause a future macOS keychain authorization prompt;
- Docker image construction remains unverified while the local daemon is down.

The relay fix is committed and pushed on remote `main`. The native diagnostic
and Status timestamp changes are local working-tree changes and a local app
installation only: they have not been committed, pushed, published, deployed,
or released.
