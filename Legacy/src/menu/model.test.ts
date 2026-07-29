import type { Quote } from "#/types";
import type { QuoteFetchResult } from "#/quotes/types";
import type { RecentAlertsBySymbol } from "#/alerts/recentAlertState";
import { buildMenuBarModel, resolveActiveQuoteResult } from "./model";

const quote = (symbol: string, price: number): Quote => ({
  symbol,
  name: symbol,
  price,
  source: "Test",
  updatedAt: 1_000,
});

describe("buildMenuBarModel", () => {
  it("builds a compact title from display symbols only", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC", "ETH"],
      titleSymbols: ["BTC", "ETH"],
      quoteResult: {
        quotes: { BTC: quote("BTC", 100), ETH: quote("ETH", 200), SOL: quote("SOL", 50) },
        missingSymbols: [],
        errors: [],
        updatedAt: 1_000,
      },
      invalidRuleTokens: [],
      isLoading: false,
      now: 12_000,
    });

    expect(model.title).toBe("BTC $100.00 · ETH $200.00");
    expect(model.items.map((item) => item.title)).toEqual([]);
  });

  it("does not show alert rule status during normal operation", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC"],
      quoteResult: { quotes: { BTC: quote("BTC", 100) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
      invalidRuleTokens: [],
      isLoading: false,
      now: 12_000,
    });

    expect(model.sections.flatMap((section) => section.items.map((item) => item.title)).join(" ")).not.toContain(
      "Alert"
    );
  });

  it("shows concise invalid rule tokens only when present", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC"],
      quoteResult: { quotes: { BTC: quote("BTC", 100) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
      invalidRuleTokens: ["bad", "ETH:-1"],
      invalidIntegerRuleTokens: ["SOL:0"],
      isLoading: false,
      now: 12_000,
    });

    expect(model.sections.at(-1)).toEqual({
      title: "Configuration",
      items: [{ title: "Ignored rules: bad, ETH:-1" }, { title: "Ignored integer rules: SOL:0" }],
    });
  });

  it("includes a concise source line for a single displayed quote source", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC"],
      quoteResult: { quotes: { BTC: quote("BTC", 100) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
      invalidRuleTokens: [],
      isLoading: false,
      now: 12_000,
    });

    const statusText = model.sections.flatMap((section) => section.items.map((item) => item.title)).join("\n");
    expect(statusText).toContain("Source: Test");
  });

  it("includes a concise joined unique source line for multiple sources", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC", "ETH"],
      quoteResult: {
        quotes: {
          BTC: { symbol: "BTC", name: "BTC", price: 100, source: "Bybit", updatedAt: 1_000 },
          ETH: { symbol: "ETH", name: "ETH", price: 200, source: "Binance", updatedAt: 1_000 },
        },
        missingSymbols: [],
        errors: [],
        updatedAt: 1_000,
      },
      invalidRuleTokens: [],
      isLoading: false,
      now: 12_000,
    });

    const statusText = model.sections.flatMap((section) => section.items.map((item) => item.title)).join("\n");
    expect(statusText).toContain("Source: Bybit, Binance");
  });

  it("keeps stale prices visible and lists their symbols in status", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC", "ETH"],
      quoteResult: {
        quotes: {
          BTC: quote("BTC", 100),
          ETH: { ...quote("ETH", 200), stale: true },
        },
        missingSymbols: [],
        errors: [],
        updatedAt: 1_000,
      },
      invalidRuleTokens: [],
      isLoading: false,
      now: 12_000,
    });

    expect(model.title).toBe("BTC $100.00 · ETH $200.00");
    const statusText = model.sections.flatMap((section) => section.items.map((item) => item.title)).join("\n");
    expect(statusText).toContain("Stale: ETH");
    expect(statusText).not.toContain("Stale: BTC");
  });

  it("returns a 'No symbols' title when displaySymbols is empty", () => {
    const model = buildMenuBarModel({
      displaySymbols: [],
      quoteResult: { quotes: {}, missingSymbols: [], errors: [], updatedAt: 1_000 },
      invalidRuleTokens: [],
      isLoading: false,
      now: 12_000,
    });

    expect(model.title).toBe("No symbols");
  });
});

it("shows dropdown rows for quote symbols that are hidden from the menu bar title by pipe", () => {
  const model = buildMenuBarModel({
    displaySymbols: ["BTC", "ETH", "NVDA", "QQQ"],
    titleSymbols: ["BTC", "ETH"],
    quoteResult: {
      quotes: { BTC: quote("BTC", 100), ETH: quote("ETH", 200), NVDA: quote("NVDA", 300), QQQ: quote("QQQ", 400) },
      missingSymbols: [],
      errors: [],
      updatedAt: 1_000,
    },
    invalidRuleTokens: [],
    isLoading: false,
    now: 12_000,
  });

  expect(model.title).toBe("BTC $100.00 · ETH $200.00");
  expect(model.items.map((item) => item.title)).toEqual(["NVDA: $300.00", "QQQ: $400.00"]);
});

it("can hide symbols in the menu bar title while preserving dropdown row symbols", () => {
  const model = buildMenuBarModel({
    displaySymbols: ["BTC", "ETH"],
    hideTitleSymbols: true,
    quoteResult: {
      quotes: { BTC: quote("BTC", 100), ETH: quote("ETH", 200) },
      missingSymbols: [],
      errors: [],
      updatedAt: 1_000,
    },
    invalidRuleTokens: [],
    isLoading: false,
    now: 12_000,
  });

  expect(model.title).toBe("$100.00 · $200.00");
  expect(model.items.map((item) => item.title)).toEqual([]);
});

it("can hide currency symbols in the title and dropdown rows", () => {
  const model = buildMenuBarModel({
    displaySymbols: ["BTC", "ETH"],
    hideCurrencySymbol: true,
    quoteResult: {
      quotes: { BTC: quote("BTC", 100), ETH: quote("ETH", 200) },
      missingSymbols: [],
      errors: [],
      updatedAt: 1_000,
    },
    invalidRuleTokens: [],
    isLoading: false,
    now: 12_000,
  });

  expect(model.title).toBe("BTC 100.00 · ETH 200.00");
  expect(model.items.map((item) => item.title)).toEqual([]);
});

it("does not mark the menu bar as loading while cached prices are visible", () => {
  const model = buildMenuBarModel({
    displaySymbols: ["BTC"],
    quoteResult: { quotes: { BTC: quote("BTC", 100) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
    invalidRuleTokens: [],
    isLoading: true,
    now: 12_000,
  });

  expect(model.title).toBe("BTC $100.00");
  expect(model.isLoading).toBe(false);
});

it("marks quotes with recent alert direction and shows a recent alerts section", () => {
  const recentAlerts: RecentAlertsBySymbol = {
    BTC: {
      symbol: "BTC",
      direction: "up",
      title: "BTC rose 1.00%",
      message: "$100.00 → $101.00",
      triggeredAt: 10_000,
    },
    QQQ: {
      symbol: "QQQ",
      direction: "down",
      title: "QQQ fell 1.00%",
      message: "$400.00 → $396.00",
      triggeredAt: 10_000,
    },
  };

  const model = buildMenuBarModel({
    displaySymbols: ["BTC", "QQQ"],
    titleSymbols: ["BTC"],
    quoteResult: {
      quotes: { BTC: quote("BTC", 101), QQQ: quote("QQQ", 396) },
      missingSymbols: [],
      errors: [],
      updatedAt: 1_000,
    },
    invalidRuleTokens: [],
    recentAlerts,
    isLoading: false,
    now: 12_000,
  });

  expect(model.title).toBe("BTC $101.00");
  expect(model.items.map((item) => item.title)).toEqual(["🔴 QQQ: $396.00"]);
  expect(model.sections[0].title).toBe("Status");
});

describe("resolveActiveQuoteResult", () => {
  const bybitResult: QuoteFetchResult = {
    quotes: { BTC: { symbol: "BTC", name: "Bitcoin", price: 100, source: "Bybit", updatedAt: 1_000 } },
    missingSymbols: [],
    errors: [],
    updatedAt: 1_000,
  };

  it("accepts a result tagged Bybit when active source is Bybit", () => {
    expect(
      resolveActiveQuoteResult({
        data: { result: bybitResult, sourceSignature: "Bybit" },
        activeSourceSignature: "Bybit",
        error: undefined,
        cachedResult: undefined,
      })
    ).toBe(bybitResult);
  });

  it("rejects a result tagged Bybit when active source is Relay", () => {
    expect(
      resolveActiveQuoteResult({
        data: { result: bybitResult, sourceSignature: "Bybit" },
        activeSourceSignature: "Relay:https://relay.example.com",
        error: undefined,
        cachedResult: undefined,
      })
    ).toBeUndefined();
  });

  it("falls back to cached result when data is stale and there is no error", () => {
    expect(
      resolveActiveQuoteResult({
        data: { result: bybitResult, sourceSignature: "Bybit" },
        activeSourceSignature: "Relay:https://relay.example.com",
        error: undefined,
        cachedResult: bybitResult,
      })
    ).toBe(bybitResult);
  });

  it("ignores an error whose signature does not match the active source", () => {
    expect(
      resolveActiveQuoteResult({
        data: undefined,
        activeSourceSignature: "Relay:https://relay.example.com",
        error: { message: "Bybit timeout", sourceSignature: "Bybit" },
        cachedResult: bybitResult,
      })
    ).toBe(bybitResult);
  });

  it("appends a matching-signature error to cached result errors", () => {
    expect(
      resolveActiveQuoteResult({
        data: undefined,
        activeSourceSignature: "Bybit",
        error: { message: "Bybit timeout", sourceSignature: "Bybit" },
        cachedResult: bybitResult,
      })
    ).toEqual({ ...bybitResult, errors: ["Bybit timeout"] });
  });

  it("creates an error-only result when matching-signature error has no cache", () => {
    expect(
      resolveActiveQuoteResult({
        data: undefined,
        activeSourceSignature: "Bybit",
        error: { message: "Bybit timeout", sourceSignature: "Bybit" },
        cachedResult: undefined,
      })
    ).toEqual({ quotes: {}, missingSymbols: [], errors: ["Bybit timeout"], updatedAt: 0 });
  });
});
