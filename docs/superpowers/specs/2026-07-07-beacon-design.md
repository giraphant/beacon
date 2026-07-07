# Beacon Design

## Summary

Beacon is a self-use Raycast menu bar extension for generalized price monitoring and recurring movement alerts. It is inspired by the existing Crypto Price extension, but it is not a fork-oriented continuation. Crypto symbols, proxy stock/ETF symbols available from exchange data sources, and future quotable symbols are treated as the same kind of watched instrument.

The first version stays intentionally small: show configured prices in the menu bar and notify when configured symbols move by a user-defined percentage from their last alert baseline.

## Product Scope

Beacon first version includes:

- One Raycast `menu-bar` command.
- Menu bar price display for symbols configured in `Coins`.
- Preference-based alert rules configured separately from displayed symbols.
- A 30-second refresh/check cadence.
- Recurring bidirectional movement alerts.
- Multi-source quote fallback.

Beacon first version excludes:

- Portfolio, holdings, cost basis, or PnL tracking.
- Market movers, search panels, or a full market dashboard.
- A dedicated rule management UI.
- Claiming proxy equity/ETF prices as official stock market data.

## Naming and Positioning

The project name is **Beacon**. The metaphor is a price signal beacon: it stays quiet until a watched price moves enough to light up.

The product should avoid crypto-only language in names, descriptions, code boundaries, and user-facing copy. Crypto is one asset class, not the product category.

## Raycast Commands and Preferences

The first version exposes one command:

- `menu-bar`
  - mode: `menu-bar`
  - interval: `30s`
  - title: `Beacon`

Preferences:

- `Coins`
  - Type: `textfield`
  - Purpose: controls which symbols appear in the menu bar.
  - Example: `BTC ETH NVDA QQQ`

- `Alert Rules`
  - Type: `textfield`
  - Purpose: controls which symbols trigger recurring movement alerts.
  - Example: `BTC:2 NVDA:1.5 SOL:1`

- No manual source picker in the first version. Prices are displayed in the source-native quote currency, usually USD/USDT, with compact formatting.

Raycast static Preferences are acceptable for the first version. A future `Manage Alerts` command using Raycast `List` and `Form` can replace or augment the text rule field if rule editing becomes annoying.

## Alert Rule Semantics

`Alert Rules` format:

```txt
SYMBOL:THRESHOLD_PERCENT SYMBOL:THRESHOLD_PERCENT
```

Examples:

```txt
BTC:2 NVDA:1.5 SOL:1
```

Meanings:

- `BTC:2` means BTC alerts whenever it moves up or down at least 2% from BTC's last alert baseline.
- Thresholds are percentages, not decimal ratios.
- Symbols are case-insensitive on input and normalized to uppercase.
- Alerts are bidirectional by default.
- There is no cooldown in the first version.

Invalid rule tokens are skipped and do not disable valid rules or price display.

## Alert Lifecycle

Each rule has persistent local state:

- `symbol`
- `lastBaselinePrice`
- `lastTriggeredAt`
- `lastTriggeredPrice`

Lifecycle:

1. When a rule first sees a valid quote, Beacon stores that price as `lastBaselinePrice` and does not notify.
2. On each refresh, Beacon compares current price with `lastBaselinePrice`.
3. If absolute movement is below the configured threshold, Beacon does nothing.
4. If movement reaches or exceeds the threshold, Beacon sends one notification.
5. If a single refresh crosses multiple threshold steps, Beacon sends one summary notification that includes total movement and crossed step count.
6. After a successful notification, Beacon updates the baseline to the current price.
7. If notification delivery fails, Beacon does not update the baseline.

Example with a 1% rule:

- Baseline: `100`
- Current: `103.2`
- Movement: `+3.2%`
- Notification: one summary saying the symbol rose 3.2% and crossed 3 one-percent steps.
- New baseline: `103.2`

## Quote Model

Beacon normalizes all source results into a quote shape:

```ts
type Quote = {
  symbol: string;
  name: string;
  price: number;
  source: string;
  updatedAt: number;
  high24h?: number;
  low24h?: number;
  change24h?: number;
};
```

The rest of the app should depend on normalized quotes, not source-specific response shapes.

## Quote Sources

Beacon should use multi-source fallback. The source layer receives a list of symbols and returns the best quotes it can find.

Initial sources can reuse the current extension's knowledge:

- Bybit for broad symbol coverage, including many proxy stock/ETF instruments.
- Binance for spot crypto coverage.
- CryptoCompare only if it remains useful as a fallback.

Source behavior:

- Missing a symbol in one source should not fail the full refresh.
- One failed source should not prevent trying other sources.
- Each quote should retain the source label used to produce it.
- Cached previous quotes may be shown if refresh fails.

For symbols such as `NVDA`, `QQQ`, or `SPY`, Beacon treats exchange-provided data as available quote data. It should avoid copy implying official equity-market pricing.

## Menu Bar Behavior

Normal UI should stay clean.

Menu bar title:

- Displays only configured `Coins` symbols that have quotes.
- Uses a compact separator such as ` · `.
- Does not show alert rule status during normal operation.

Menu dropdown:

- Shows price details for displayed symbols.
- Shows minimal source/refresh status.
- Shows Settings action.
- May show concise configuration errors only when helpful.

No dedicated alert status list is needed in the first version.

## Error Handling

- Quote refresh failure: use fallback sources where possible; if all sources fail, show cached prices when available and a minimal refresh failure status.
- Missing symbol: omit that symbol from price display; do not fail other symbols.
- Invalid alert rule token: skip the token and continue parsing other rules.
- First-time rule: create baseline without notifying.
- Notification failure: keep existing baseline so the alert can retry later.
- Empty `Coins`: show a clear empty-state title rather than crashing.
- Empty `Alert Rules`: disable alerts while preserving price display.

## Testing Strategy

Unit tests should cover:

- Display symbol parsing.
- Alert rule parsing.
- Case normalization.
- Invalid rule token handling.
- 1%, 1.5%, and 2% threshold calculations.
- Bidirectional alert triggering.
- No alert below threshold.
- First quote creates baseline without alerting.
- A large price jump creates one summary alert with a step count.
- Baseline updates only after successful notification.
- Quote fallback merges source results without one missing symbol breaking all symbols.

Manual verification should cover:

- Raycast menu bar command displays configured prices.
- Preference changes affect displayed symbols and alert rules.
- Notifications fire with expected wording using controlled test prices or a test helper.
- Build and development commands run with `RAY_Target=x` for Raycast 2 Beta compatibility.

## Implementation Notes

The implementation should prefer small modules:

- Preference parsing.
- Quote source adapters.
- Quote fallback orchestration.
- Alert rule parsing.
- Alert state storage.
- Alert evaluation.
- Menu bar view model.

The menu bar component should stay thin and render an already-prepared view model.
