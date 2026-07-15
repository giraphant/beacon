# Beacon Source Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore explicit Bybit/Binance direct quote selection alongside the Relay path while preserving cache, freshness, and alert safety.

**Architecture:** A small quote-source dispatcher selects either the existing Relay client or the restored direct-exchange fallback. Both paths return a neutral `QuoteFetchResult`; the menu command keeps one cache and source-aware request signature. Relay failures never create direct traffic, while Bybit and Binance continue to fall back to each other.

**Tech Stack:** TypeScript, React, Raycast API, `@raycast/utils`, Jest, native `fetch`, Raycast CLI.

## Global Constraints

- `Preferred Source` values are exactly `Bybit`, `Binance`, and `Relay`; default is `Bybit`.
- Bybit and Binance direct modes fall back to each other in preferred order.
- Relay mode performs exactly one request per refresh and never falls back to direct exchange access.
- Relay request timeout remains exactly 3,000 ms.
- Relay token appears only in the `Authorization: Bearer` header and in-memory promise dependencies.
- Only successful results update `quote-cache`; failures keep cached prices visible.
- Quotes with `stale: true` remain visible but never reach alert evaluation.
- Raycast 2 commands build with `RAY_Target=x`.
- No new npm dependencies.

---

## File Structure

- `src/quotes/types.ts` — neutral `QuoteFetchResult` contract shared by all quote paths.
- `src/quotes/source.ts` — source union, direct/Relay dispatch, and source request identity.
- `src/quotes/source.test.ts` — proves explicit routing and source signatures.
- `src/quotes/bybit.ts`, `binance.ts`, `fetchWithRetry.ts`, `fallback.ts` — restored direct implementation.
- Corresponding direct quote tests — restored regression coverage.
- `src/quotes/relay.ts` — existing Relay behavior, importing the neutral result type.
- `src/menu-bar.tsx` — preference wiring, dispatch call, and source-aware request signature.
- `src/menu/model.ts` — imports only the neutral result type; rendering behavior stays unchanged.
- `package.json` — restores `source` and makes Relay credentials optional for direct users.

---

### Task 1: Restore the direct quote path behind a neutral result contract

**Files:**
- Create: `src/quotes/types.ts`
- Restore: `src/quotes/bybit.ts`
- Restore: `src/quotes/binance.ts`
- Restore: `src/quotes/fetchWithRetry.ts`
- Restore: `src/quotes/fallback.ts`
- Restore tests: `src/quotes/bybit.test.ts`, `src/quotes/binance.test.ts`, `src/quotes/fetchWithRetry.test.ts`, `src/quotes/fallback.test.ts`
- Modify: `src/quotes/relay.ts:1-11`
- Modify: `src/menu/model.ts:1-3`

**Interfaces:**
- Produces: `QuoteFetchResult` from `#/quotes/types`.
- Produces: `PreferredQuoteSource = "Bybit" | "Binance"` and `fetchQuotesWithFallback(symbols, preferredSource)` from `#/quotes/fallback`.
- Consumes: existing `Quote` from `#/types`.

- [ ] **Step 1: Restore only the old direct tests**

```bash
git checkout 03596e8 -- \
  src/quotes/bybit.test.ts \
  src/quotes/binance.test.ts \
  src/quotes/fetchWithRetry.test.ts \
  src/quotes/fallback.test.ts
```

- [ ] **Step 2: Run the restored tests and verify they fail because implementations are absent**

Run:

```bash
npm test -- --runInBand \
  src/quotes/bybit.test.ts \
  src/quotes/binance.test.ts \
  src/quotes/fetchWithRetry.test.ts \
  src/quotes/fallback.test.ts
```

Expected: FAIL with module-not-found errors for the deleted direct quote modules.

- [ ] **Step 3: Create the neutral quote result type**

Create `src/quotes/types.ts`:

```ts
import type { Quote } from "#/types";

export type QuoteFetchResult = {
  quotes: Record<string, Quote>;
  missingSymbols: string[];
  errors: string[];
  updatedAt: number;
};
```

- [ ] **Step 4: Restore the direct implementations from the last pre-Relay commit**

```bash
git checkout 03596e8 -- \
  src/quotes/bybit.ts \
  src/quotes/binance.ts \
  src/quotes/fetchWithRetry.ts \
  src/quotes/fallback.ts
```

In `src/quotes/fallback.ts`, remove its local `QuoteFetchResult` declaration and add:

```ts
import type { QuoteFetchResult } from "#/quotes/types";
export type { QuoteFetchResult } from "#/quotes/types";
```

Keep the restored interfaces:

```ts
export type PreferredQuoteSource = "Bybit" | "Binance";

export async function fetchQuotesWithFallback(
  symbols: string[],
  preferredSource: PreferredQuoteSource
): Promise<QuoteFetchResult>;
```

- [ ] **Step 5: Point Relay and menu model at the neutral type**

In `src/quotes/relay.ts`, replace the local type with:

```ts
import type { QuoteFetchResult } from "#/quotes/types";
export type { QuoteFetchResult } from "#/quotes/types";
```

In `src/menu/model.ts`, use:

```ts
import type { QuoteFetchResult } from "#/quotes/types";
```

- [ ] **Step 6: Run all direct and Relay quote tests**

Run:

```bash
npm test -- --runInBand \
  src/quotes/bybit.test.ts \
  src/quotes/binance.test.ts \
  src/quotes/fetchWithRetry.test.ts \
  src/quotes/fallback.test.ts \
  src/quotes/relay.test.ts
```

Expected: 5 suites PASS; no direct test changes beyond import compatibility.

- [ ] **Step 7: Commit the restored direct path**

```bash
git add src/quotes src/menu/model.ts
git commit -m "feat: restore direct quote clients"
```

---

### Task 2: Add explicit quote-source dispatch

**Files:**
- Create: `src/quotes/source.ts`
- Create: `src/quotes/source.test.ts`

**Interfaces:**
- Consumes: `fetchRelayQuotes(symbols, relayUrl, relayToken)`.
- Consumes: `fetchQuotesWithFallback(symbols, preferredSource)`.
- Produces: `QuoteSource = "Bybit" | "Binance" | "Relay"`.
- Produces: `fetchQuotesForSource(symbols, source, relayUrl, relayToken): Promise<QuoteFetchResult>`.
- Produces: `createQuoteSourceSignature(source, relayUrl): string`.

- [ ] **Step 1: Write failing source dispatch tests**

Create `src/quotes/source.test.ts`:

```ts
import { fetchQuotesWithFallback } from "./fallback";
import { fetchRelayQuotes } from "./relay";
import { createQuoteSourceSignature, fetchQuotesForSource } from "./source";

jest.mock("./fallback", () => ({ fetchQuotesWithFallback: jest.fn() }));
jest.mock("./relay", () => ({ fetchRelayQuotes: jest.fn() }));

const directResult = { quotes: {}, missingSymbols: [], errors: [], updatedAt: 1 };
const relayResult = { quotes: {}, missingSymbols: [], errors: [], updatedAt: 2 };

const fallbackMock = fetchQuotesWithFallback as jest.MockedFunction<typeof fetchQuotesWithFallback>;
const relayMock = fetchRelayQuotes as jest.MockedFunction<typeof fetchRelayQuotes>;

describe("quote source dispatch", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fallbackMock.mockResolvedValue(directResult);
    relayMock.mockResolvedValue(relayResult);
  });

  it.each(["Bybit", "Binance"] as const)("routes %s through direct fallback", async (source) => {
    await expect(fetchQuotesForSource(["BTC"], source, "https://relay.example.com", "secret")).resolves.toBe(
      directResult
    );
    expect(fallbackMock).toHaveBeenCalledWith(["BTC"], source);
    expect(relayMock).not.toHaveBeenCalled();
  });

  it("routes Relay through exactly one relay call", async () => {
    await expect(fetchQuotesForSource(["BTC"], "Relay", "https://relay.example.com", "secret")).resolves.toBe(
      relayResult
    );
    expect(relayMock).toHaveBeenCalledTimes(1);
    expect(relayMock).toHaveBeenCalledWith(["BTC"], "https://relay.example.com", "secret");
    expect(fallbackMock).not.toHaveBeenCalled();
  });

  it("keys direct requests only by source and Relay requests by URL", () => {
    expect(createQuoteSourceSignature("Bybit", "https://unused.example.com")).toBe("Bybit");
    expect(createQuoteSourceSignature("Relay", " https://relay.example.com ")).toBe(
      "Relay:https://relay.example.com"
    );
  });
});
```

- [ ] **Step 2: Run the source test and verify it fails because the module is absent**

Run:

```bash
npm test -- --runInBand src/quotes/source.test.ts
```

Expected: FAIL with `Cannot find module './source'`.

- [ ] **Step 3: Implement the minimal dispatcher**

Create `src/quotes/source.ts`:

```ts
import { fetchQuotesWithFallback, type PreferredQuoteSource } from "#/quotes/fallback";
import { fetchRelayQuotes } from "#/quotes/relay";
import type { QuoteFetchResult } from "#/quotes/types";

export type QuoteSource = PreferredQuoteSource | "Relay";

export function fetchQuotesForSource(
  symbols: string[],
  source: QuoteSource,
  relayUrl: string | undefined,
  relayToken: string | undefined
): Promise<QuoteFetchResult> {
  return source === "Relay"
    ? fetchRelayQuotes(symbols, relayUrl, relayToken)
    : fetchQuotesWithFallback(symbols, source);
}

export function createQuoteSourceSignature(source: QuoteSource, relayUrl: string | undefined): string {
  return source === "Relay" ? `Relay:${relayUrl?.trim() ?? ""}` : source;
}
```

- [ ] **Step 4: Run the source dispatch tests**

Run:

```bash
npm test -- --runInBand src/quotes/source.test.ts
```

Expected: 4 tests PASS, including two parameterized direct cases.

- [ ] **Step 5: Commit the dispatcher**

```bash
git add src/quotes/source.ts src/quotes/source.test.ts
git commit -m "feat: dispatch selectable quote sources"
```

---

### Task 3: Restore the preference and wire the menu command

**Files:**
- Modify: `package.json:20-63`
- Modify: `src/menu-bar.tsx:15-53,83-87,120-128`
- Generated: `raycast-env.d.ts`

**Interfaces:**
- Consumes: `QuoteSource`, `fetchQuotesForSource`, and `createQuoteSourceSignature` from `#/quotes/source`.
- Consumes: `QuoteFetchResult` from `#/quotes/types`.

- [ ] **Step 1: Restore the source preference and make Relay credentials mode-optional**

Insert before Relay URL in `package.json`:

```json
{
  "name": "source",
  "title": "Preferred Source",
  "description": "Use Relay, or prefer one direct exchange and fall back to the other",
  "type": "dropdown",
  "default": "Bybit",
  "required": false,
  "data": [
    { "title": "Bybit", "value": "Bybit" },
    { "title": "Binance", "value": "Binance" },
    { "title": "Relay", "value": "Relay" }
  ]
}
```

Change both Relay preferences from:

```json
"required": true
```

to:

```json
"required": false
```

- [ ] **Step 2: Wire menu-bar dispatch and source-aware signatures**

Replace the Relay-only import in `src/menu-bar.tsx` with:

```ts
import {
  createQuoteSourceSignature,
  fetchQuotesForSource,
  type QuoteSource,
} from "#/quotes/source";
import type { QuoteFetchResult } from "#/quotes/types";
```

Add to `MenuBarPreferences`:

```ts
source?: QuoteSource;
```

Change `fetchTaggedQuotes` to:

```ts
async function fetchTaggedQuotes(
  symbols: string[],
  ruleSignature: string,
  quoteSymbolSignature: string,
  source: QuoteSource,
  relayUrl: string | undefined,
  relayToken: string | undefined
): Promise<TaggedQuoteFetchResult> {
  return {
    result: await fetchQuotesForSource(symbols, source, relayUrl, relayToken),
    ruleSignature,
    quoteSymbolSignature,
  };
}
```

Before building `quoteSymbolSignature`, add:

```ts
const source = preferences.source ?? "Bybit";
const relayUrl = preferences.relayUrl?.trim() ?? "";
const quoteSourceSignature = createQuoteSourceSignature(source, relayUrl);
```

Build the signature with:

```ts
const quoteSymbolSignature = useMemo(
  () => `${quoteSourceSignature}:${createQuoteSymbolSignature(quoteSymbols)}`,
  [quoteSourceSignature, quoteSymbols]
);
```

Pass the selected source through `usePromise`:

```ts
[quoteSymbols, ruleSignature, quoteSymbolSignature, source, relayUrl, preferences.relayToken]
```

- [ ] **Step 3: Run focused source, menu, Relay, and alert tests**

Run:

```bash
npm test -- --runInBand \
  src/quotes/source.test.ts \
  src/quotes/fallback.test.ts \
  src/quotes/relay.test.ts \
  src/menu/model.test.ts \
  src/alerts/freshQuoteAlertScheduler.test.ts
```

Expected: all focused suites PASS; stale filtering tests remain unchanged.

- [ ] **Step 4: Run Raycast lint to validate the preference schema and generate formatting feedback**

Run:

```bash
npm run lint
```

Expected: package validation, icon validation, ESLint, and Prettier all report `ready`.

If formatting fails, run `npm run fix-lint`, inspect the diff, and rerun the focused tests and `npm run lint`.

- [ ] **Step 5: Build for Raycast 2 and accept generated preference types**

Run:

```bash
RAY_Target=x npm run build
```

Expected: TypeScript checked and `built extension successfully`; `raycast-env.d.ts` contains:

```ts
"source": "Bybit" | "Binance" | "Relay",
"relayUrl": string,
"relayToken": string,
```

Raycast's generated declaration does not encode `required: false`; runtime code therefore keeps these values optional in `MenuBarPreferences`.

- [ ] **Step 6: Commit preference and menu wiring**

```bash
git add package.json raycast-env.d.ts src/menu-bar.tsx
git commit -m "feat: restore preferred quote source"
```

---

### Task 4: Full verification, review, integration, and publication

**Files:**
- Verify all changed files.
- Update parent repository gitlink after Beacon merge.

**Interfaces:**
- Produces: merged Beacon commit on `giraphant/beacon/main`.
- Produces: parent gitlink on `giraphant/raycast-plugins/main` pointing to that merged commit.
- Produces: new `inol` Private Store version.

- [ ] **Step 1: Run the complete automated verification**

Run:

```bash
npm test -- --runInBand
npm run lint
RAY_Target=x npm run build
git diff --check
git status --short
```

Expected: every Jest suite passes, lint passes, build succeeds, no whitespace errors, and only intended feature files differ from `origin/main`.

- [ ] **Step 2: Confirm no token or unintended direct fallback from Relay**

Run:

```bash
grep -RInE 'test-relay-token-value|Authorization.*query|relayToken.*signature' src package.json || true
grep -RIn 'fetchQuotesForSource' src
```

Expected: only the test fixture token appears in `relay.test.ts`; dispatcher has one Relay branch and one direct branch, with no catch-based cross-mode fallback.

- [ ] **Step 3: Push the branch and open a Beacon PR**

```bash
git push -u origin feat/source-selection
gh pr create \
  --repo giraphant/beacon \
  --base main \
  --head feat/source-selection \
  --title "feat: restore selectable quote sources" \
  --body-file /tmp/beacon-source-selection-pr.md
```

The PR body must list direct fallback behavior, explicit Relay behavior, cache/stale safety, restored tests, full verification results, and end with:

```text
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

- [ ] **Step 4: Run Codex against the final PR diff**

Run:

```bash
/Applications/ChatGPT.app/Contents/Resources/codex \
  -C "$PWD" \
  review --base origin/main
```

Expected: no valid unresolved findings. Apply only confirmed fixes, rerun Step 1, commit and push, then rerun Codex until clear.

- [ ] **Step 5: Squash-merge the Beacon PR and verify remote main**

```bash
gh pr merge --repo giraphant/beacon --squash --delete-branch
git fetch origin main
git checkout main
git pull --ff-only origin main
git rev-parse HEAD
git rev-parse origin/main
```

Expected: PR state `MERGED`; local and remote Beacon main hashes match.

- [ ] **Step 6: Update and push the parent submodule pointer**

From the parent main worktree, check out the merged Beacon commit in `beacon`, stage only `beacon`, and verify the pre-existing parent `package-lock.json` remains untouched:

```bash
git add beacon
git diff --cached --submodule=short -- beacon
git commit -m "chore: bump beacon submodule for source selection" \
  -m "Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin main
```

Expected: the parent commit changes exactly one gitlink.

- [ ] **Step 7: Publish merged Beacon main to the private store**

Run from the merged Beacon main checkout:

```bash
npm run publish -- -I
```

Expected: lint and build pass, extension uploads, a new version is created, and Raycast reports:

```text
published extension to your private organization inol store
```

- [ ] **Step 8: Final remote verification**

Run:

```bash
git ls-remote https://github.com/giraphant/beacon.git refs/heads/main
git ls-remote https://github.com/giraphant/raycast-plugins.git refs/heads/main
gh pr view --repo giraphant/beacon --json state,mergeCommit,url
```

Expected: Beacon main is the PR merge commit, parent main contains its gitlink update, PR is merged, and both working trees are clean except the pre-existing untracked parent `package-lock.json`.
