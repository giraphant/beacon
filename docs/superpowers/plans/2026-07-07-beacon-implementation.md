# Beacon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Beacon as a self-use Raycast menu bar extension that displays configured prices and sends recurring percentage movement alerts.

**Architecture:** The Raycast component stays thin and renders a menu bar view model. Pure TypeScript modules parse preferences, normalize quotes, evaluate alert rules, and orchestrate alert delivery; Raycast APIs are isolated to storage, toast notification, preferences, and UI integration.

**Tech Stack:** Raycast API, Raycast Utils, React, TypeScript, Jest, ts-jest, Node 16-compatible CommonJS.

## Global Constraints

- Project name is `Beacon`.
- The first version exposes one Raycast `menu-bar` command with interval `30s`.
- Avoid crypto-only language in names, descriptions, code boundaries, and user-facing copy.
- `Coins` controls menu bar symbols; `Alert Rules` controls recurring alerts.
- `Alert Rules` format is `SYMBOL:THRESHOLD_PERCENT SYMBOL:THRESHOLD_PERCENT`, for example `BTC:2 NVDA:1.5 SOL:1`.
- Alerts are bidirectional by default.
- There is no cooldown in the first version.
- First valid quote for a rule creates the baseline without notifying.
- A single refresh crossing multiple threshold steps sends one summary alert.
- Notification failure must not update the baseline.
- Use multi-source fallback, initially Bybit linear then Binance spot.
- Treat proxy stock/ETF symbols as available quote symbols, not official equity-market pricing.
- Run build and development commands with `RAY_Target=x` for Raycast 2 Beta compatibility.

---

## File Structure

- `package.json` — Raycast manifest, scripts, dependencies, command preferences.
- `tsconfig.json` — strict TypeScript config with `#/*` path alias.
- `jest.config.js` — ts-jest config using the TypeScript path alias.
- `.eslintrc.json` — Raycast-compatible TypeScript lint config.
- `.prettierrc` — formatting config matching the existing Raycast workspace.
- `assets/command-icon.png` — generated Beacon command icon.
- `src/types.ts` — shared domain types.
- `src/constants.ts` — known symbol names and route hints.
- `src/config/preferences.ts` — pure parsing for display symbols and alert rules.
- `src/utils/format.ts` — compact price, percent, and age formatting.
- `src/alerts/evaluateAlert.ts` — pure alert decision logic.
- `src/alerts/runAlerts.ts` — alert orchestration with injected state and notifier dependencies.
- `src/alerts/raycastState.ts` — LocalStorage-backed alert state adapter.
- `src/alerts/raycastNotifier.ts` — Raycast toast notifier.
- `src/quotes/fetchWithRetry.ts` — fetch helper with timeout and retry.
- `src/quotes/bybit.ts` — Bybit linear quote adapter.
- `src/quotes/binance.ts` — Binance spot quote adapter.
- `src/quotes/fallback.ts` — quote source fallback orchestration.
- `src/menu/model.ts` — menu bar title/dropdown view model builder.
- `src/menu-bar.tsx` — Raycast menu bar command.
- `src/**/*.test.ts` — Jest tests next to the modules under test.

---

### Task 1: Scaffold the Raycast extension

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `jest.config.js`
- Create: `.eslintrc.json`
- Create: `.prettierrc`
- Create: `src/types.ts`
- Create: `src/menu-bar.tsx`
- Create: `assets/command-icon.png`

**Interfaces:**
- Consumes: the committed design spec at `docs/superpowers/specs/2026-07-07-beacon-design.md`.
- Produces: a buildable Raycast extension shell with the `Preferences.MenuBar` generated type available after Raycast build.

- [ ] **Step 1: Create the manifest and scripts**

Write `package.json`:

```json
{
  "$schema": "https://www.raycast.com/schemas/extension.json",
  "name": "beacon",
  "title": "Beacon",
  "description": "A price signal beacon for Raycast menu bar alerts",
  "icon": "command-icon.png",
  "author": "giraphant",
  "owner": "giraphant",
  "categories": ["Finance"],
  "license": "MIT",
  "commands": [
    {
      "name": "menu-bar",
      "title": "Beacon",
      "description": "Watch prices and receive movement alerts",
      "mode": "menu-bar",
      "interval": "30s"
    }
  ],
  "preferences": [
    {
      "title": "Coins",
      "name": "coins",
      "description": "Symbols to show in the menu bar, separated by spaces, commas, or vertical bars",
      "type": "textfield",
      "placeholder": "BTC ETH NVDA QQQ",
      "default": "BTC ETH NVDA QQQ",
      "required": false
    },
    {
      "title": "Alert Rules",
      "name": "alertRules",
      "description": "Recurring alert rules such as BTC:2 NVDA:1.5 SOL:1",
      "type": "textfield",
      "placeholder": "BTC:2 NVDA:1.5 SOL:1",
      "default": "",
      "required": false
    }
  ],
  "dependencies": {
    "@raycast/api": "^1.104.19",
    "@raycast/utils": "^2.2.7"
  },
  "devDependencies": {
    "@types/jest": "^29.5.12",
    "@types/node": "~16.10.0",
    "@types/react": "^17.0.28",
    "@typescript-eslint/eslint-plugin": "^5.0.0",
    "@typescript-eslint/parser": "^5.0.0",
    "eslint": "^7.32.0",
    "eslint-config-prettier": "^8.3.0",
    "jest": "^29.7.0",
    "prettier": "^2.5.1",
    "ts-jest": "^29.1.2",
    "typescript": "^4.4.3"
  },
  "scripts": {
    "test": "jest",
    "build": "RAY_Target=x ray build -e dist",
    "dev": "RAY_Target=x ray develop",
    "fix-lint": "ray lint --fix",
    "lint": "ray lint",
    "publish": "ray publish"
  }
}
```

- [ ] **Step 2: Create TypeScript, Jest, lint, and formatting config**

Write `tsconfig.json`:

```json
{
  "$schema": "https://json.schemastore.org/tsconfig",
  "display": "Node 16",
  "include": ["src/**/*"],
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "#/*": ["src/*"]
    },
    "lib": ["es2021", "dom"],
    "module": "commonjs",
    "target": "es2021",
    "strict": true,
    "isolatedModules": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "jsx": "react-jsx",
    "resolveJsonModule": true
  }
}
```

Write `jest.config.js`:

```js
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { pathsToModuleNameMapper } = require("ts-jest");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { compilerOptions } = require("./tsconfig.json");

/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  modulePaths: [compilerOptions.baseUrl],
  moduleNameMapper: pathsToModuleNameMapper(compilerOptions.paths),
};
```

Write `.eslintrc.json`:

```json
{
  "root": true,
  "env": {
    "es2020": true,
    "node": true
  },
  "parser": "@typescript-eslint/parser",
  "plugins": ["@typescript-eslint"],
  "extends": ["eslint:recommended", "plugin:@typescript-eslint/recommended", "prettier"]
}
```

Write `.prettierrc`:

```json
{
  "printWidth": 120,
  "singleQuote": false
}
```

- [ ] **Step 3: Create the minimal Raycast entrypoint and shared type shell**

Write `src/types.ts`:

```ts
export type Quote = {
  symbol: string;
  name: string;
  price: number;
  source: string;
  updatedAt: number;
  high24h?: number;
  low24h?: number;
  change24h?: number;
};

export type AlertRule = {
  symbol: string;
  thresholdPercent: number;
  enabled: boolean;
};

export type AlertState = {
  symbol: string;
  lastBaselinePrice: number;
  lastTriggeredAt?: number;
  lastTriggeredPrice?: number;
};

export type ParsedAlertRules = {
  rules: AlertRule[];
  invalidTokens: string[];
};
```

Write `src/menu-bar.tsx`:

```tsx
import { MenuBarExtra, openCommandPreferences } from "@raycast/api";

export default function Command() {
  return (
    <MenuBarExtra title="Beacon">
      <MenuBarExtra.Section>
        <MenuBarExtra.Item title="Settings" onAction={openCommandPreferences} shortcut={{ key: ",", modifiers: ["cmd"] }} />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
```

- [ ] **Step 4: Generate a local Beacon icon**

Run this command from the repository root:

```bash
python3 - <<'PY'
import base64
from pathlib import Path
Path('assets').mkdir(exist_ok=True)
png = base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAABy0lEQVR4nO2aTU7DMBCFv4qKxA24Aiuw5Aa0qbpD'
    'u0FF6i5ZgOsAFoAqcQsuQQVkxA2QkFYkJY1RkqZpS5zm7MRnSJr4/WMnTuyEP8MwDAMAAAAAAAAAAAAA4DkG'
    '4LPzDHPN6TVOC5t0Pr3m1qz8A3R0Hx3fXYf7eN8T6JQwC3TBOu5v8g7VtqMFSqKFsJbAJd5V3H3hGJnmC9RF'
    'cwAd6xxPyKLYHkAXxQH0TJgFOMh4K9uQK4CqjwG4K6gC6tPpBvhrNPRl8I7YNcnWDBApnq1TZoAcLJpTswAw'
    '0mktzADA6aU5OQMAp5fm5AAAxM6N/QAAnF6ekwMAkE43zckBAMiiOzkAAKNTd3IAAMaW9uQAAKQ8s3kAwC9o'
    'E0+CbZASoG2adUH2JtoG2QJc5uQGYPAv4aA/4Uu3iS2fJb4v0D7IJsgWYD9IE2QLsJ+kCbIF2I/SBNkC7Cfp'
    'AmyBdiP0gTZAuwn6QJsgXYj9IE2QLsJ+kCbIF2I/SBNkC7CfpAmyBdiP0gTZAuwn6QJsgXYj9IG2YbYFqjW1m'
    'l2FHgBxB2wBDid7WzR6A8QTs4yf4R1gAtpkH4A14Aj4DT8DjF9wCAAAAAAAAAAAAAPyJH2nVhBCtv2+IAAAA'
    'AElFTkSuQmCC'
)
Path('assets/command-icon.png').write_bytes(png)
PY
```

- [ ] **Step 5: Install dependencies and verify the shell builds**

Run:

```bash
npm install
npm test -- --passWithNoTests
npm run build
```

Expected:

- `npm install` creates `package-lock.json`.
- `npm test -- --passWithNoTests` exits successfully.
- `npm run build` exits successfully and generates `raycast-env.d.ts` plus `dist/`.

- [ ] **Step 6: Commit scaffold**

Run:

```bash
git add package.json package-lock.json tsconfig.json jest.config.js .eslintrc.json .prettierrc src/types.ts src/menu-bar.tsx assets/command-icon.png raycast-env.d.ts
git commit -m "$(cat <<'EOF'
Initialize Beacon Raycast extension.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Preference parsing and formatting

**Files:**
- Create: `src/config/preferences.ts`
- Create: `src/config/preferences.test.ts`
- Create: `src/utils/format.ts`
- Create: `src/utils/format.test.ts`
- Modify: `src/types.ts`

**Interfaces:**
- Consumes: `AlertRule`, `ParsedAlertRules` from `src/types.ts`.
- Produces: `parseSymbolsText(text: string): string[]`, `parseAlertRulesText(text: string): ParsedAlertRules`, `formatPrice(price: number): string`, `formatPercent(value: number): string`, `formatAge(updatedAt: number, now: number): string`.

- [ ] **Step 1: Write failing parser tests**

Write `src/config/preferences.test.ts`:

```ts
import { parseAlertRulesText, parseSymbolsText } from "./preferences";

describe("parseSymbolsText", () => {
  it("normalizes space, comma, and vertical-bar separated symbols", () => {
    expect(parseSymbolsText("btc, eth | NVDA  qqq")).toEqual(["BTC", "ETH", "NVDA", "QQQ"]);
  });

  it("deduplicates symbols while preserving first occurrence order", () => {
    expect(parseSymbolsText("BTC eth btc ETH sol")).toEqual(["BTC", "ETH", "SOL"]);
  });
});

describe("parseAlertRulesText", () => {
  it("parses symbol threshold pairs", () => {
    expect(parseAlertRulesText("BTC:2 NVDA:1.5 sol:1")).toEqual({
      rules: [
        { symbol: "BTC", thresholdPercent: 2, enabled: true },
        { symbol: "NVDA", thresholdPercent: 1.5, enabled: true },
        { symbol: "SOL", thresholdPercent: 1, enabled: true },
      ],
      invalidTokens: [],
    });
  });

  it("skips invalid tokens and keeps valid rules", () => {
    expect(parseAlertRulesText("BTC:2 nope ETH:-1 SOL:0 JUP:1.25")).toEqual({
      rules: [
        { symbol: "BTC", thresholdPercent: 2, enabled: true },
        { symbol: "JUP", thresholdPercent: 1.25, enabled: true },
      ],
      invalidTokens: ["nope", "ETH:-1", "SOL:0"],
    });
  });

  it("lets the last duplicate rule win", () => {
    expect(parseAlertRulesText("BTC:2 ETH:1 BTC:3")).toEqual({
      rules: [
        { symbol: "ETH", thresholdPercent: 1, enabled: true },
        { symbol: "BTC", thresholdPercent: 3, enabled: true },
      ],
      invalidTokens: [],
    });
  });
});
```

- [ ] **Step 2: Write failing formatter tests**

Write `src/utils/format.test.ts`:

```ts
import { formatAge, formatPercent, formatPrice } from "./format";

describe("formatPrice", () => {
  it("formats compact source-native prices", () => {
    expect(formatPrice(103245.18)).toBe("$103,245");
    expect(formatPrice(421.456)).toBe("$421.46");
    expect(formatPrice(0.123456)).toBe("$0.1235");
  });
});

describe("formatPercent", () => {
  it("formats signed percentage values", () => {
    expect(formatPercent(3.245)).toBe("+3.25%");
    expect(formatPercent(-1)).toBe("-1.00%");
  });
});

describe("formatAge", () => {
  it("formats seconds and minutes", () => {
    expect(formatAge(1_000, 12_000)).toBe("11s ago");
    expect(formatAge(1_000, 181_000)).toBe("3m ago");
  });
});
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
npm test -- src/config/preferences.test.ts src/utils/format.test.ts --runInBand
```

Expected: FAIL because `src/config/preferences.ts` and `src/utils/format.ts` do not exist.

- [ ] **Step 4: Implement parsers and formatters**

Write `src/config/preferences.ts`:

```ts
import type { AlertRule, ParsedAlertRules } from "#/types";

const SYMBOL_SPLIT_PATTERN = /[\s,|]+/;
const RULE_PATTERN = /^([A-Za-z0-9._-]+):(\d+(?:\.\d+)?)$/;

export function parseSymbolsText(text: string): string[] {
  const seen = new Set<string>();
  const symbols: string[] = [];

  for (const rawToken of text.split(SYMBOL_SPLIT_PATTERN)) {
    const symbol = normalizeSymbol(rawToken);
    if (!symbol || seen.has(symbol)) {
      continue;
    }
    seen.add(symbol);
    symbols.push(symbol);
  }

  return symbols;
}

export function parseAlertRulesText(text: string): ParsedAlertRules {
  const rulesBySymbol = new Map<string, AlertRule>();
  const invalidTokens: string[] = [];

  for (const rawToken of text.split(SYMBOL_SPLIT_PATTERN)) {
    const token = rawToken.trim();
    if (!token) {
      continue;
    }

    const match = token.match(RULE_PATTERN);
    if (!match) {
      invalidTokens.push(token);
      continue;
    }

    const symbol = normalizeSymbol(match[1]);
    const thresholdPercent = Number(match[2]);
    if (!symbol || !Number.isFinite(thresholdPercent) || thresholdPercent <= 0) {
      invalidTokens.push(token);
      continue;
    }

    if (rulesBySymbol.has(symbol)) {
      rulesBySymbol.delete(symbol);
    }
    rulesBySymbol.set(symbol, { symbol, thresholdPercent, enabled: true });
  }

  return { rules: [...rulesBySymbol.values()], invalidTokens };
}

function normalizeSymbol(value: string) {
  return value.trim().toUpperCase();
}
```

Write `src/utils/format.ts`:

```ts
const PRICE_FORMATTERS = [
  { max: 1, digits: 4 },
  { max: 100, digits: 3 },
  { max: 1000, digits: 2 },
] as const;

export function formatPrice(price: number): string {
  const digits = PRICE_FORMATTERS.find((formatter) => Math.abs(price) < formatter.max)?.digits ?? 0;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(price);
}

export function formatPercent(value: number): string {
  const sign = value > 0 ? "+" : "";
  return `${sign}${value.toFixed(2)}%`;
}

export function formatAge(updatedAt: number, now: number): string {
  const ageSeconds = Math.max(0, Math.round((now - updatedAt) / 1000));
  if (ageSeconds < 60) {
    return `${ageSeconds}s ago`;
  }
  return `${Math.floor(ageSeconds / 60)}m ago`;
}
```

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
npm test -- src/config/preferences.test.ts src/utils/format.test.ts --runInBand
```

Expected: PASS.

- [ ] **Step 6: Commit parsing and formatting**

Run:

```bash
git add src/config/preferences.ts src/config/preferences.test.ts src/utils/format.ts src/utils/format.test.ts src/types.ts
git commit -m "$(cat <<'EOF'
Add Beacon preference parsing and formatting.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Alert evaluation logic

**Files:**
- Create: `src/alerts/evaluateAlert.ts`
- Create: `src/alerts/evaluateAlert.test.ts`
- Modify: `src/types.ts`

**Interfaces:**
- Consumes: `AlertRule`, `AlertState`, `Quote` from `src/types.ts`.
- Produces: `evaluateAlert(rule: AlertRule, quote: Quote, state: AlertState | undefined, now: number): AlertEvaluation`.

- [ ] **Step 1: Extend shared alert types**

Modify `src/types.ts` to include these exports:

```ts
export type AlertNotification = {
  symbol: string;
  title: string;
  message: string;
  movementPercent: number;
  thresholdPercent: number;
  crossedSteps: number;
  currentPrice: number;
  baselinePrice: number;
};

export type AlertEvaluation =
  | { kind: "initialize"; nextState: AlertState }
  | { kind: "none" }
  | { kind: "trigger"; notification: AlertNotification; nextState: AlertState };
```

Keep the existing `Quote`, `AlertRule`, `AlertState`, and `ParsedAlertRules` exports.

- [ ] **Step 2: Write failing alert evaluation tests**

Write `src/alerts/evaluateAlert.test.ts`:

```ts
import type { AlertRule, AlertState, Quote } from "#/types";
import { evaluateAlert } from "./evaluateAlert";

const rule: AlertRule = { symbol: "BTC", thresholdPercent: 1, enabled: true };
const quote = (price: number): Quote => ({
  symbol: "BTC",
  name: "Bitcoin",
  price,
  source: "Test",
  updatedAt: 1_000,
});
const state = (lastBaselinePrice: number): AlertState => ({ symbol: "BTC", lastBaselinePrice });

describe("evaluateAlert", () => {
  it("initializes baseline on first quote without alerting", () => {
    expect(evaluateAlert(rule, quote(100), undefined, 10_000)).toEqual({
      kind: "initialize",
      nextState: { symbol: "BTC", lastBaselinePrice: 100 },
    });
  });

  it("does nothing below threshold", () => {
    expect(evaluateAlert(rule, quote(100.5), state(100), 10_000)).toEqual({ kind: "none" });
  });

  it("triggers on upward threshold movement", () => {
    const result = evaluateAlert(rule, quote(101), state(100), 10_000);
    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.nextState).toEqual({
      symbol: "BTC",
      lastBaselinePrice: 101,
      lastTriggeredAt: 10_000,
      lastTriggeredPrice: 101,
    });
    expect(result.notification.title).toBe("BTC rose 1.00%");
    expect(result.notification.crossedSteps).toBe(1);
  });

  it("triggers on downward threshold movement", () => {
    const result = evaluateAlert(rule, quote(98), state(100), 10_000);
    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.title).toBe("BTC fell 2.00%");
    expect(result.notification.crossedSteps).toBe(2);
  });

  it("summarizes multiple crossed steps in one notification", () => {
    const result = evaluateAlert(rule, quote(103.2), state(100), 10_000);
    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.message).toBe("$100 → $103.20, crossed 3 × 1.00% steps");
    expect(result.notification.crossedSteps).toBe(3);
  });

  it("ignores disabled rules", () => {
    expect(evaluateAlert({ ...rule, enabled: false }, quote(103), state(100), 10_000)).toEqual({ kind: "none" });
  });
});
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
npm test -- src/alerts/evaluateAlert.test.ts --runInBand
```

Expected: FAIL because `evaluateAlert.ts` does not exist.

- [ ] **Step 4: Implement alert evaluation**

Write `src/alerts/evaluateAlert.ts`:

```ts
import type { AlertEvaluation, AlertRule, AlertState, Quote } from "#/types";
import { formatPercent, formatPrice } from "#/utils/format";

export function evaluateAlert(
  rule: AlertRule,
  quote: Quote,
  state: AlertState | undefined,
  now: number
): AlertEvaluation {
  if (!rule.enabled) {
    return { kind: "none" };
  }

  if (!state) {
    return {
      kind: "initialize",
      nextState: {
        symbol: rule.symbol,
        lastBaselinePrice: quote.price,
      },
    };
  }

  const movementPercent = ((quote.price - state.lastBaselinePrice) / state.lastBaselinePrice) * 100;
  const absoluteMovementPercent = Math.abs(movementPercent);
  if (absoluteMovementPercent < rule.thresholdPercent) {
    return { kind: "none" };
  }

  const crossedSteps = Math.floor(absoluteMovementPercent / rule.thresholdPercent);
  const verb = movementPercent > 0 ? "rose" : "fell";
  const nextState: AlertState = {
    symbol: rule.symbol,
    lastBaselinePrice: quote.price,
    lastTriggeredAt: now,
    lastTriggeredPrice: quote.price,
  };

  return {
    kind: "trigger",
    notification: {
      symbol: rule.symbol,
      title: `${rule.symbol} ${verb} ${formatPercent(movementPercent)}`,
      message: `${formatPrice(state.lastBaselinePrice)} → ${formatPrice(quote.price)}, crossed ${crossedSteps} × ${formatPercent(
        rule.thresholdPercent
      ).replace("+", "")} steps`,
      movementPercent,
      thresholdPercent: rule.thresholdPercent,
      crossedSteps,
      currentPrice: quote.price,
      baselinePrice: state.lastBaselinePrice,
    },
    nextState,
  };
}
```

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
npm test -- src/alerts/evaluateAlert.test.ts src/utils/format.test.ts --runInBand
```

Expected: PASS.

- [ ] **Step 6: Commit alert evaluation**

Run:

```bash
git add src/types.ts src/alerts/evaluateAlert.ts src/alerts/evaluateAlert.test.ts
git commit -m "$(cat <<'EOF'
Add recurring alert evaluation.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Alert orchestration with injected state and notifier

**Files:**
- Create: `src/alerts/runAlerts.ts`
- Create: `src/alerts/runAlerts.test.ts`

**Interfaces:**
- Consumes: `evaluateAlert(rule, quote, state, now)` from `src/alerts/evaluateAlert.ts`.
- Produces: `runAlerts(input: RunAlertsInput): Promise<RunAlertsResult>`.

- [ ] **Step 1: Write failing orchestration tests**

Write `src/alerts/runAlerts.test.ts`:

```ts
import type { AlertNotification, AlertRule, AlertState, Quote } from "#/types";
import { runAlerts } from "./runAlerts";

const quote = (symbol: string, price: number): Quote => ({ symbol, name: symbol, price, source: "Test", updatedAt: 1_000 });
const rule = (symbol: string, thresholdPercent: number): AlertRule => ({ symbol, thresholdPercent, enabled: true });

describe("runAlerts", () => {
  it("creates baseline states without notifying", async () => {
    const saved: AlertState[] = [];
    const notifications: AlertNotification[] = [];

    const result = await runAlerts({
      rules: [rule("BTC", 1)],
      quotes: { BTC: quote("BTC", 100) },
      now: 10_000,
      getState: async () => undefined,
      saveState: async (state) => saved.push(state),
      notify: async (notification) => notifications.push(notification),
    });

    expect(result).toEqual({ initialized: 1, triggered: 0, skipped: 0, failed: 0 });
    expect(saved).toEqual([{ symbol: "BTC", lastBaselinePrice: 100 }]);
    expect(notifications).toEqual([]);
  });

  it("saves next state only after notification succeeds", async () => {
    const saved: AlertState[] = [];

    const result = await runAlerts({
      rules: [rule("BTC", 1)],
      quotes: { BTC: quote("BTC", 102) },
      now: 10_000,
      getState: async () => ({ symbol: "BTC", lastBaselinePrice: 100 }),
      saveState: async (state) => saved.push(state),
      notify: async () => undefined,
    });

    expect(result).toEqual({ initialized: 0, triggered: 1, skipped: 0, failed: 0 });
    expect(saved).toEqual([{ symbol: "BTC", lastBaselinePrice: 102, lastTriggeredAt: 10_000, lastTriggeredPrice: 102 }]);
  });

  it("does not save trigger state when notification fails", async () => {
    const saved: AlertState[] = [];

    const result = await runAlerts({
      rules: [rule("BTC", 1)],
      quotes: { BTC: quote("BTC", 102) },
      now: 10_000,
      getState: async () => ({ symbol: "BTC", lastBaselinePrice: 100 }),
      saveState: async (state) => saved.push(state),
      notify: async () => {
        throw new Error("notification failed");
      },
    });

    expect(result).toEqual({ initialized: 0, triggered: 0, skipped: 0, failed: 1 });
    expect(saved).toEqual([]);
  });

  it("skips rules without quotes", async () => {
    const result = await runAlerts({
      rules: [rule("BTC", 1)],
      quotes: {},
      now: 10_000,
      getState: async () => undefined,
      saveState: async () => undefined,
      notify: async () => undefined,
    });

    expect(result).toEqual({ initialized: 0, triggered: 0, skipped: 1, failed: 0 });
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- src/alerts/runAlerts.test.ts --runInBand
```

Expected: FAIL because `runAlerts.ts` does not exist.

- [ ] **Step 3: Implement orchestration**

Write `src/alerts/runAlerts.ts`:

```ts
import type { AlertNotification, AlertRule, AlertState, Quote } from "#/types";
import { evaluateAlert } from "./evaluateAlert";

export type RunAlertsInput = {
  rules: AlertRule[];
  quotes: Record<string, Quote>;
  now: number;
  getState: (symbol: string) => Promise<AlertState | undefined>;
  saveState: (state: AlertState) => Promise<void>;
  notify: (notification: AlertNotification) => Promise<void>;
};

export type RunAlertsResult = {
  initialized: number;
  triggered: number;
  skipped: number;
  failed: number;
};

export async function runAlerts(input: RunAlertsInput): Promise<RunAlertsResult> {
  const result: RunAlertsResult = { initialized: 0, triggered: 0, skipped: 0, failed: 0 };

  for (const rule of input.rules) {
    const quote = input.quotes[rule.symbol];
    if (!quote) {
      result.skipped += 1;
      continue;
    }

    const state = await input.getState(rule.symbol);
    const evaluation = evaluateAlert(rule, quote, state, input.now);

    if (evaluation.kind === "none") {
      continue;
    }

    if (evaluation.kind === "initialize") {
      await input.saveState(evaluation.nextState);
      result.initialized += 1;
      continue;
    }

    try {
      await input.notify(evaluation.notification);
      await input.saveState(evaluation.nextState);
      result.triggered += 1;
    } catch {
      result.failed += 1;
    }
  }

  return result;
}
```

- [ ] **Step 4: Run tests to verify pass**

Run:

```bash
npm test -- src/alerts/runAlerts.test.ts src/alerts/evaluateAlert.test.ts --runInBand
```

Expected: PASS.

- [ ] **Step 5: Commit alert orchestration**

Run:

```bash
git add src/alerts/runAlerts.ts src/alerts/runAlerts.test.ts
git commit -m "$(cat <<'EOF'
Add alert orchestration.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Quote source adapters and fallback

**Files:**
- Create: `src/constants.ts`
- Create: `src/quotes/fetchWithRetry.ts`
- Create: `src/quotes/bybit.ts`
- Create: `src/quotes/binance.ts`
- Create: `src/quotes/fallback.ts`
- Create: `src/quotes/fallback.test.ts`

**Interfaces:**
- Consumes: `Quote` from `src/types.ts`.
- Produces: `fetchQuotesWithFallback(symbols: string[]): Promise<QuoteFetchResult>` and `type QuoteFetchResult = { quotes: Record<string, Quote>; missingSymbols: string[]; errors: string[]; updatedAt: number }`.

- [ ] **Step 1: Write failing fallback tests**

Write `src/quotes/fallback.test.ts`:

```ts
import type { Quote } from "#/types";
import { fetchQuotesFromSources, type QuoteSource } from "./fallback";

const quote = (symbol: string, source: string): Quote => ({
  symbol,
  name: symbol,
  price: 100,
  source,
  updatedAt: 1_000,
});

describe("fetchQuotesFromSources", () => {
  it("uses earlier sources first and fills missing symbols from later sources", async () => {
    const sources: QuoteSource[] = [
      { name: "Bybit", fetchQuotes: async () => ({ BTC: quote("BTC", "Bybit") }) },
      { name: "Binance", fetchQuotes: async () => ({ ETH: quote("ETH", "Binance") }) },
    ];

    const result = await fetchQuotesFromSources(["BTC", "ETH"], sources, 10_000);

    expect(Object.keys(result.quotes)).toEqual(["BTC", "ETH"]);
    expect(result.quotes.BTC.source).toBe("Bybit");
    expect(result.quotes.ETH.source).toBe("Binance");
    expect(result.missingSymbols).toEqual([]);
  });

  it("records failed source names and still returns available quotes", async () => {
    const sources: QuoteSource[] = [
      { name: "Bybit", fetchQuotes: async () => { throw new Error("down"); } },
      { name: "Binance", fetchQuotes: async () => ({ BTC: quote("BTC", "Binance") }) },
    ];

    const result = await fetchQuotesFromSources(["BTC", "SOL"], sources, 10_000);

    expect(result.quotes.BTC.source).toBe("Binance");
    expect(result.missingSymbols).toEqual(["SOL"]);
    expect(result.errors).toEqual(["Bybit: down"]);
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- src/quotes/fallback.test.ts --runInBand
```

Expected: FAIL because `fallback.ts` does not exist.

- [ ] **Step 3: Implement constants and fallback orchestration**

Write `src/constants.ts`:

```ts
export const INSTRUMENTS: Record<string, { name: string }> = {
  BTC: { name: "Bitcoin" },
  ETH: { name: "Ethereum" },
  BNB: { name: "BNB" },
  SOL: { name: "Solana" },
  XRP: { name: "XRP" },
  JUP: { name: "Jupiter" },
  JTO: { name: "Jito" },
  SUI: { name: "Sui" },
  JLP: { name: "Jupiter Perps LP" },
  HYPE: { name: "Hyperliquid" },
  AAPL: { name: "Apple" },
  AMZN: { name: "Amazon" },
  COIN: { name: "Coinbase" },
  GOOG: { name: "Google" },
  GOOGL: { name: "Google" },
  HOOD: { name: "Robinhood" },
  INTC: { name: "Intel" },
  META: { name: "Meta" },
  MSTR: { name: "MicroStrategy" },
  NVDA: { name: "Nvidia" },
  QQQ: { name: "Invesco QQQ" },
  SPY: { name: "SPDR S&P 500" },
  TSLA: { name: "Tesla" },
  TSM: { name: "TSMC" },
  XPL: { name: "Plasma" },
};

export function getInstrumentName(symbol: string) {
  return INSTRUMENTS[symbol]?.name ?? symbol;
}
```

Write `src/quotes/fallback.ts`:

```ts
import type { Quote } from "#/types";
import { fetchBinanceSpotQuotes } from "./binance";
import { fetchBybitLinearQuotes } from "./bybit";

export type QuoteFetchResult = {
  quotes: Record<string, Quote>;
  missingSymbols: string[];
  errors: string[];
  updatedAt: number;
};

export type QuoteSource = {
  name: string;
  fetchQuotes: (symbols: string[]) => Promise<Record<string, Quote>>;
};

const DEFAULT_SOURCES: QuoteSource[] = [
  { name: "Bybit", fetchQuotes: fetchBybitLinearQuotes },
  { name: "Binance", fetchQuotes: fetchBinanceSpotQuotes },
];

export function fetchQuotesWithFallback(symbols: string[]) {
  return fetchQuotesFromSources(symbols, DEFAULT_SOURCES, Date.now());
}

export async function fetchQuotesFromSources(
  symbols: string[],
  sources: QuoteSource[],
  updatedAt: number
): Promise<QuoteFetchResult> {
  const uniqueSymbols = [...new Set(symbols)];
  const quotes: Record<string, Quote> = {};
  const errors: string[] = [];

  for (const source of sources) {
    const missing = uniqueSymbols.filter((symbol) => !quotes[symbol]);
    if (missing.length === 0) {
      break;
    }

    try {
      const sourceQuotes = await source.fetchQuotes(missing);
      for (const symbol of missing) {
        if (sourceQuotes[symbol] && !quotes[symbol]) {
          quotes[symbol] = sourceQuotes[symbol];
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      errors.push(`${source.name}: ${message}`);
    }
  }

  return {
    quotes,
    missingSymbols: uniqueSymbols.filter((symbol) => !quotes[symbol]),
    errors,
    updatedAt,
  };
}
```

- [ ] **Step 4: Implement fetch helper and source adapters**

Write `src/quotes/fetchWithRetry.ts`:

```ts
const DEFAULT_TIMEOUT_MS = 4500;
const DEFAULT_ATTEMPTS = 2;

export async function fetchJsonWithRetry<T>(url: string, options: { timeoutMs?: number; attempts?: number } = {}): Promise<T> {
  const attempts = options.attempts ?? DEFAULT_ATTEMPTS;
  let lastError: Error | undefined;

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await fetchWithTimeout(url, options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
      if (!response.ok) {
        throw new Error(`Request failed (${response.status} ${response.statusText || "HTTP error"}): ${url}`);
      }
      return (await response.json()) as T;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (attempt === attempts - 1) {
        throw lastError;
      }
    }
  }

  throw lastError ?? new Error(`Request failed: ${url}`);
}

function fetchWithTimeout(url: string, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  return fetch(url, { signal: controller.signal }).finally(() => clearTimeout(timeout));
}
```

Write `src/quotes/bybit.ts`:

```ts
import { getInstrumentName } from "#/constants";
import type { Quote } from "#/types";
import { fetchJsonWithRetry } from "./fetchWithRetry";

const LINEAR_TICKER_URL = "https://api.bytick.com/v5/market/tickers?category=linear";

type BybitTicker = {
  symbol: string;
  lastPrice: string;
  highPrice24h: string;
  lowPrice24h: string;
};

type BybitTickersResponse = {
  retCode: number;
  retMsg?: string;
  result?: { list?: unknown[] };
};

export async function fetchBybitLinearQuotes(symbols: string[]): Promise<Record<string, Quote>> {
  const data = await fetchJsonWithRetry<BybitTickersResponse>(LINEAR_TICKER_URL, { attempts: 1, timeoutMs: 8000 });
  if (data.retCode !== 0) {
    throw new Error(data.retMsg || `Bybit returned retCode ${data.retCode}`);
  }

  const targetSymbols = new Set(symbols.map((symbol) => `${symbol}USDT`));
  const list = Array.isArray(data.result?.list) ? data.result.list : [];
  const updatedAt = Date.now();
  const quotes: Record<string, Quote> = {};

  for (const item of list) {
    if (!isBybitTicker(item) || !targetSymbols.has(item.symbol)) {
      continue;
    }
    const symbol = item.symbol.replace(/USDT$/, "");
    quotes[symbol] = {
      symbol,
      name: getInstrumentName(symbol),
      price: Number(item.lastPrice),
      high24h: Number(item.highPrice24h),
      low24h: Number(item.lowPrice24h),
      source: "Bybit linear (USDT)",
      updatedAt,
    };
  }

  return quotes;
}

function isBybitTicker(value: unknown): value is BybitTicker {
  if (!value || typeof value !== "object") {
    return false;
  }
  const ticker = value as Record<string, unknown>;
  return (
    typeof ticker.symbol === "string" &&
    typeof ticker.lastPrice === "string" &&
    typeof ticker.highPrice24h === "string" &&
    typeof ticker.lowPrice24h === "string"
  );
}
```

Write `src/quotes/binance.ts`:

```ts
import { getInstrumentName } from "#/constants";
import type { Quote } from "#/types";
import { fetchJsonWithRetry } from "./fetchWithRetry";

const SPOT_TICKER_URL = "https://api.binance.com/api/v3/ticker/24hr";

type BinanceTicker = {
  symbol: string;
  lastPrice: string;
  highPrice: string;
  lowPrice: string;
};

export async function fetchBinanceSpotQuotes(symbols: string[]): Promise<Record<string, Quote>> {
  const data = await fetchJsonWithRetry<unknown>(getTickersUrl(symbols), { attempts: 1, timeoutMs: 3500 });
  if (!Array.isArray(data)) {
    return {};
  }

  const targetSymbols = new Set(symbols.map((symbol) => `${symbol}USDT`));
  const updatedAt = Date.now();
  const quotes: Record<string, Quote> = {};

  for (const item of data) {
    if (!isBinanceTicker(item) || !targetSymbols.has(item.symbol)) {
      continue;
    }
    const symbol = item.symbol.replace(/USDT$/, "");
    quotes[symbol] = {
      symbol,
      name: getInstrumentName(symbol),
      price: Number(item.lastPrice),
      high24h: Number(item.highPrice),
      low24h: Number(item.lowPrice),
      source: "Binance spot (USDT)",
      updatedAt,
    };
  }

  return quotes;
}

function isBinanceTicker(value: unknown): value is BinanceTicker {
  if (!value || typeof value !== "object") {
    return false;
  }
  const ticker = value as Record<string, unknown>;
  return (
    typeof ticker.symbol === "string" &&
    typeof ticker.lastPrice === "string" &&
    typeof ticker.highPrice === "string" &&
    typeof ticker.lowPrice === "string"
  );
}

function getTickersUrl(symbols: string[]) {
  const pairSymbols = JSON.stringify(symbols.map((symbol) => `${symbol}USDT`));
  return `${SPOT_TICKER_URL}?symbols=${encodeURIComponent(pairSymbols)}&type=MINI`;
}
```

- [ ] **Step 5: Run tests to verify pass**

Run:

```bash
npm test -- src/quotes/fallback.test.ts --runInBand
```

Expected: PASS.

- [ ] **Step 6: Commit quote fallback**

Run:

```bash
git add src/constants.ts src/quotes/fetchWithRetry.ts src/quotes/bybit.ts src/quotes/binance.ts src/quotes/fallback.ts src/quotes/fallback.test.ts
git commit -m "$(cat <<'EOF'
Add quote source fallback.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Menu bar view model

**Files:**
- Create: `src/menu/model.ts`
- Create: `src/menu/model.test.ts`

**Interfaces:**
- Consumes: `QuoteFetchResult` from `src/quotes/fallback.ts`, `formatPrice`, `formatAge` from `src/utils/format.ts`.
- Produces: `buildMenuBarModel(input: BuildMenuBarModelInput): MenuBarModel`.

- [ ] **Step 1: Write failing menu model tests**

Write `src/menu/model.test.ts`:

```ts
import type { Quote } from "#/types";
import { buildMenuBarModel } from "./model";

const quote = (symbol: string, price: number): Quote => ({ symbol, name: symbol, price, source: "Test", updatedAt: 1_000 });

describe("buildMenuBarModel", () => {
  it("builds a compact title from display symbols only", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC", "ETH"],
      quoteResult: { quotes: { BTC: quote("BTC", 100), ETH: quote("ETH", 200), SOL: quote("SOL", 50) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
      invalidRuleTokens: [],
      isLoading: false,
      now: 12_000,
    });

    expect(model.title).toBe("BTC $100.00 · ETH $200.00");
    expect(model.items.map((item) => item.title)).toEqual(["BTC: $100.00", "ETH: $200.00"]);
  });

  it("does not show alert rule status during normal operation", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC"],
      quoteResult: { quotes: { BTC: quote("BTC", 100) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
      invalidRuleTokens: [],
      isLoading: false,
      now: 12_000,
    });

    expect(model.sections.flatMap((section) => section.items.map((item) => item.title)).join(" ")).not.toContain("Alert");
  });

  it("shows concise invalid rule tokens only when present", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC"],
      quoteResult: { quotes: { BTC: quote("BTC", 100) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
      invalidRuleTokens: ["bad", "ETH:-1"],
      isLoading: false,
      now: 12_000,
    });

    expect(model.sections.at(-1)).toEqual({ title: "Configuration", items: [{ title: "Ignored rules: bad, ETH:-1" }] });
  });
});
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
npm test -- src/menu/model.test.ts --runInBand
```

Expected: FAIL because `model.ts` does not exist.

- [ ] **Step 3: Implement menu model**

Write `src/menu/model.ts`:

```ts
import type { Quote } from "#/types";
import type { QuoteFetchResult } from "#/quotes/fallback";
import { formatAge, formatPrice } from "#/utils/format";

export type MenuItemModel = { title: string };
export type MenuSectionModel = { title?: string; items: MenuItemModel[] };
export type MenuBarModel = {
  title: string;
  items: MenuItemModel[];
  sections: MenuSectionModel[];
};

export type BuildMenuBarModelInput = {
  displaySymbols: string[];
  quoteResult: QuoteFetchResult | undefined;
  invalidRuleTokens: string[];
  isLoading: boolean;
  now: number;
};

export function buildMenuBarModel(input: BuildMenuBarModelInput): MenuBarModel {
  const quotes = input.quoteResult?.quotes ?? {};
  const displayQuotes = input.displaySymbols.map((symbol) => quotes[symbol]).filter((quote): quote is Quote => Boolean(quote));

  const title = buildTitle(input.displaySymbols, displayQuotes, input.isLoading);
  const items = displayQuotes.map((quote) => ({ title: `${quote.symbol}: ${formatPrice(quote.price)}` }));
  const sections: MenuSectionModel[] = [];

  if (input.quoteResult) {
    const statusItems = [
      input.quoteResult.updatedAt ? { title: `Updated: ${formatAge(input.quoteResult.updatedAt, input.now)}` } : undefined,
      input.quoteResult.missingSymbols.length > 0 ? { title: `Not found: ${input.quoteResult.missingSymbols.join(", ")}` } : undefined,
      input.quoteResult.errors.length > 0 ? { title: `Refresh issues: ${input.quoteResult.errors.join("; ")}` } : undefined,
    ].filter((item): item is MenuItemModel => Boolean(item));

    if (statusItems.length > 0) {
      sections.push({ title: "Status", items: statusItems });
    }
  }

  if (input.invalidRuleTokens.length > 0) {
    sections.push({
      title: "Configuration",
      items: [{ title: `Ignored rules: ${input.invalidRuleTokens.join(", ")}` }],
    });
  }

  return { title, items, sections };
}

function buildTitle(displaySymbols: string[], displayQuotes: Quote[], isLoading: boolean) {
  if (displaySymbols.length === 0) {
    return "No symbols";
  }
  if (displayQuotes.length === 0) {
    return isLoading ? "Loading..." : "No prices found";
  }
  return displayQuotes.map((quote) => `${quote.symbol} ${formatPrice(quote.price)}`).join(" · ");
}
```

- [ ] **Step 4: Run tests to verify pass**

Run:

```bash
npm test -- src/menu/model.test.ts src/utils/format.test.ts --runInBand
```

Expected: PASS.

- [ ] **Step 5: Commit menu model**

Run:

```bash
git add src/menu/model.ts src/menu/model.test.ts
git commit -m "$(cat <<'EOF'
Add Beacon menu bar view model.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Raycast storage, notification, and menu bar integration

**Files:**
- Create: `src/alerts/raycastState.ts`
- Create: `src/alerts/raycastNotifier.ts`
- Modify: `src/menu-bar.tsx`

**Interfaces:**
- Consumes: `parseSymbolsText`, `parseAlertRulesText`, `fetchQuotesWithFallback`, `runAlerts`, `buildMenuBarModel`.
- Produces: a working Raycast menu bar command that displays prices and checks alert rules every refresh.

- [ ] **Step 1: Create Raycast state and notifier adapters**

Write `src/alerts/raycastState.ts`:

```ts
import { LocalStorage } from "@raycast/api";
import type { AlertState } from "#/types";

const STORAGE_PREFIX = "alert-state:";

export async function getAlertState(symbol: string): Promise<AlertState | undefined> {
  const value = await LocalStorage.getItem<string>(`${STORAGE_PREFIX}${symbol}`);
  if (!value) {
    return undefined;
  }

  try {
    return JSON.parse(value) as AlertState;
  } catch {
    return undefined;
  }
}

export async function saveAlertState(state: AlertState): Promise<void> {
  await LocalStorage.setItem(`${STORAGE_PREFIX}${state.symbol}`, JSON.stringify(state));
}
```

Write `src/alerts/raycastNotifier.ts`:

```ts
import { showToast, Toast } from "@raycast/api";
import type { AlertNotification } from "#/types";

export async function notifyAlert(notification: AlertNotification): Promise<void> {
  await showToast({
    style: Toast.Style.Success,
    title: notification.title,
    message: notification.message,
  });
}
```

- [ ] **Step 2: Integrate the menu bar command**

Replace `src/menu-bar.tsx` with:

```tsx
import { MenuBarExtra, getPreferenceValues, openCommandPreferences } from "@raycast/api";
import { useCachedState, usePromise } from "@raycast/utils";
import { useEffect, useMemo } from "react";
import { getAlertState, saveAlertState } from "#/alerts/raycastState";
import { notifyAlert } from "#/alerts/raycastNotifier";
import { runAlerts } from "#/alerts/runAlerts";
import { parseAlertRulesText, parseSymbolsText } from "#/config/preferences";
import { buildMenuBarModel } from "#/menu/model";
import { fetchQuotesWithFallback, type QuoteFetchResult } from "#/quotes/fallback";

type MenuBarPreferences = {
  coins?: string;
  alertRules?: string;
};

export default function Command() {
  const preferences = getPreferenceValues<MenuBarPreferences>();
  const displaySymbols = useMemo(() => parseSymbolsText(preferences.coins ?? ""), [preferences.coins]);
  const parsedRules = useMemo(() => parseAlertRulesText(preferences.alertRules ?? ""), [preferences.alertRules]);
  const quoteSymbols = useMemo(
    () => [...new Set([...displaySymbols, ...parsedRules.rules.map((rule) => rule.symbol)])],
    [displaySymbols, parsedRules.rules]
  );

  const [cachedQuotes, setCachedQuotes] = useCachedState<QuoteFetchResult | undefined>("quote-cache", undefined);
  const { data, isLoading, error } = usePromise(fetchQuotesWithFallback, [quoteSymbols], {
    execute: quoteSymbols.length > 0,
    onData: (result) => setCachedQuotes(result),
    onError: () => undefined,
  });

  const quoteResult = data ?? cachedQuotes;

  useEffect(() => {
    if (!quoteResult || parsedRules.rules.length === 0) {
      return;
    }

    runAlerts({
      rules: parsedRules.rules,
      quotes: quoteResult.quotes,
      now: Date.now(),
      getState: getAlertState,
      saveState: saveAlertState,
      notify: notifyAlert,
    });
  }, [quoteResult?.updatedAt, parsedRules.rules]);

  const model = buildMenuBarModel({
    displaySymbols,
    quoteResult: error && cachedQuotes ? { ...cachedQuotes, errors: [error.message] } : quoteResult,
    invalidRuleTokens: parsedRules.invalidTokens,
    isLoading,
    now: Date.now(),
  });

  return (
    <MenuBarExtra isLoading={isLoading} title={model.title}>
      {model.items.map((item) => (
        <MenuBarExtra.Item key={item.title} title={item.title} onAction={() => undefined} />
      ))}
      {model.sections.map((section) => (
        <MenuBarExtra.Section key={section.title ?? "section"} title={section.title}>
          {section.items.map((item) => (
            <MenuBarExtra.Item key={item.title} title={item.title} onAction={() => undefined} />
          ))}
        </MenuBarExtra.Section>
      ))}
      <MenuBarExtra.Section>
        <MenuBarExtra.Item title="Settings" onAction={openCommandPreferences} shortcut={{ key: ",", modifiers: ["cmd"] }} />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
```

- [ ] **Step 3: Run full automated tests**

Run:

```bash
npm test -- --runInBand
```

Expected: PASS.

- [ ] **Step 4: Run type/build verification**

Run:

```bash
npm run build
```

Expected: PASS with `RAY_Target=x ray build -e dist`.

- [ ] **Step 5: Commit Raycast integration**

Run:

```bash
git add src/alerts/raycastState.ts src/alerts/raycastNotifier.ts src/menu-bar.tsx raycast-env.d.ts

git commit -m "$(cat <<'EOF'
Connect Beacon menu bar alerts.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Final verification and PR preparation

**Files:**
- Modify: files changed only if verification exposes a concrete defect.

**Interfaces:**
- Consumes: all Beacon implementation tasks.
- Produces: a tested branch ready for review and pull request creation.

- [ ] **Step 1: Run full test suite**

Run:

```bash
npm test -- --runInBand
```

Expected: PASS.

- [ ] **Step 2: Run Raycast build**

Run:

```bash
npm run build
```

Expected: PASS.

- [ ] **Step 3: Run Raycast development command for manual verification**

Run:

```bash
npm run dev
```

Expected: Raycast launches Beacon in development mode. Verify these manual cases:

- `Coins = BTC ETH NVDA QQQ` shows available prices in the menu bar title.
- Empty `Coins` shows `No symbols` without crashing.
- `Alert Rules = BTC:1` establishes a baseline on first refresh without notifying.
- A controlled test price path or local code probe confirms a later 1% movement produces one toast and updates state.
- Invalid `Alert Rules` tokens show only the concise configuration message in the dropdown.

- [ ] **Step 4: Run code review/audit before PR**

Run a final review focused on correctness, race conditions, alert semantics, and Raycast API usage. Include a second independent review pass before creating the PR. The requested Codex-style audit should be treated as a final adversarial discussion: look for ways the implementation violates the spec, surprises the user, or sends incorrect alerts.

- [ ] **Step 5: Check git state**

Run:

```bash
git status --short --branch
git log --oneline -n 8
```

Expected: all intended code is committed or intentionally staged for the final PR commit.

---

## Self-Review

- Spec coverage: Tasks cover the single menu-bar command, separate `Coins` and `Alert Rules`, 30-second cadence, bidirectional recurring alerts, first-price baseline initialization, multi-step summary alerts, notification failure baseline behavior, Bybit/Binance fallback, clean menu display, and Raycast 2 Beta build target.
- Placeholder scan: no incomplete markers or undefined implementation steps remain in this plan.
- Type consistency: `AlertRule`, `AlertState`, `AlertNotification`, `AlertEvaluation`, `Quote`, `QuoteFetchResult`, `parseSymbolsText`, `parseAlertRulesText`, `evaluateAlert`, `runAlerts`, `fetchQuotesWithFallback`, and `buildMenuBarModel` are defined before downstream tasks consume them.
