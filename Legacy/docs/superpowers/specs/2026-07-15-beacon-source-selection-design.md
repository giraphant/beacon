# Beacon Source Selection Design

## Context

Beacon originally let users choose Bybit or Binance as a preferred direct source, with the other exchange used as fallback. The Relay integration replaced that path with a required Relay URL and token. Beacon should support both deployment styles without silently changing network paths or weakening Relay freshness handling.

## Goals

- Restore the `Preferred Source` preference non-destructively.
- Support `Bybit`, `Binance`, and `Relay` as explicit user choices.
- Default users without a saved choice to Bybit.
- Preserve direct exchange fallback between Bybit and Binance.
- Keep Relay mode to exactly one authenticated Relay request per refresh.
- Preserve cached display values on refresh failures.
- Never trigger alerts from Relay quotes marked stale.

## Non-goals

- Automatic fallback from Relay to direct exchange access.
- Combining Relay and direct quotes in one refresh.
- Changing the Relay service or its exchange priority.
- Publishing Relay credentials in source, URLs, logs, cache, or request signatures.

## Preferences and migration

Restore the preference key `source` with the title `Preferred Source` and these values:

1. `Bybit` — default.
2. `Binance`.
3. `Relay`.

Using the original key allows Raycast to reuse a previously retained Bybit or Binance value. Users without a stored value receive the Bybit default.

Keep `relayUrl` and `relayToken`, but make them optional in the extension manifest so direct-mode users are not blocked by irrelevant required fields. Relay mode validates both values at request time. Raycast cannot conditionally hide preferences, so the Relay fields remain visible in every mode.

## Quote architecture

Both paths return a shared `QuoteFetchResult`:

```ts
type QuoteFetchResult = {
  quotes: Record<string, Quote>;
  missingSymbols: string[];
  errors: string[];
  updatedAt: number;
};
```

Place this neutral contract under `src/quotes/` and have the menu model, Relay client, and direct fallback use it.

The menu command has one dispatch boundary:

- `Relay` calls `fetchRelayQuotes` once with the selected symbols, Relay URL, and token.
- `Bybit` calls the direct fallback with Bybit first and Binance second.
- `Binance` calls the direct fallback with Binance first and Bybit second.

Restore the previous direct exchange modules and focused tests from the last pre-Relay commit. Keep the Relay client unchanged except for importing the shared result contract.

## Request identity and cache

The request signature includes the selected source and symbol set. Relay mode also includes the normalized Relay URL. The token remains only an in-memory promise dependency so changing it triggers a refresh without persisting it or placing it in a signature.

Only successful results update `quote-cache`. On any failure, Beacon keeps the previous successful result visible and adds the current refresh error for display. Switching source invalidates results created for the previous source.

## Failure behavior

- Direct mode tries the preferred exchange first and uses the other exchange for failed or missing symbols.
- Relay mode never falls back to direct exchange access.
- Relay authentication, rate limit, timeout, unavailable, and malformed-response errors keep cached values visible.
- With no cache, the menu displays an empty result plus the refresh error.

This makes the selected network path explicit and avoids unexpected direct access when a user intentionally chose Relay.

## Freshness and alerts

Relay quotes preserve `source`, `updatedAt`, and `stale`. Stale Relay quotes remain visible and are listed in Status, but the shared alert scheduler filters them before percent and integer alert evaluation.

Direct quotes do not set `stale` and continue through the existing alert path as fresh quotes.

## Security

- Relay tokens are sent only through the `Authorization: Bearer` header.
- Tokens are not placed in URLs, logs, cache entries, request signatures, or fixtures.
- Relay URLs require HTTPS except for loopback development addresses.
- Direct mode uses only public market-data endpoints and no exchange API keys.
- Selecting Relay does not silently create direct exchange traffic.

## Verification

Add or restore coverage for:

- Preference parsing for Bybit, Binance, and Relay.
- Bybit-first and Binance-first direct fallback.
- Relay dispatch making exactly one request with no direct fallback.
- Source and Relay URL request identity changes.
- Cached display behavior on each path's failures.
- Relay stale quotes remaining visible but excluded from alerts.
- Token absence from URLs, signatures, logs, and committed fixtures.

Run the full Jest suite, Raycast lint, and the Raycast 2 build with `RAY_Target=x`. Run Codex review against the final PR diff, fix confirmed findings, merge the Beacon PR, update the parent workspace submodule pointer, then publish the merged Beacon main to the `inol` Private Store.
