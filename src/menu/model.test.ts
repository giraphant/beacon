import type { Quote } from "#/types";
import { buildMenuBarModel } from "./model";

const quote = (symbol: string, price: number): Quote => ({ symbol, name: symbol, price, source: "Test", updatedAt: 1_000 });

describe("buildMenuBarModel", () => {
  it("builds a compact title from display symbols only", () => {
    const model = buildMenuBarModel({
      displaySymbols: ["BTC", "ETH"],
      titleSymbols: ["BTC", "ETH"],
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
  expect(model.items.map((item) => item.title)).toEqual(["BTC: $100.00", "ETH: $200.00", "NVDA: $300.00", "QQQ: $400.00"]);
});

it("can hide symbols in the menu bar title while preserving dropdown row symbols", () => {
  const model = buildMenuBarModel({
    displaySymbols: ["BTC", "ETH"],
    hideTitleSymbols: true,
    quoteResult: { quotes: { BTC: quote("BTC", 100), ETH: quote("ETH", 200) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
    invalidRuleTokens: [],
    isLoading: false,
    now: 12_000,
  });

  expect(model.title).toBe("$100.00 · $200.00");
  expect(model.items.map((item) => item.title)).toEqual(["BTC: $100.00", "ETH: $200.00"]);
});

it("can hide currency symbols in the title and dropdown rows", () => {
  const model = buildMenuBarModel({
    displaySymbols: ["BTC", "ETH"],
    hideCurrencySymbol: true,
    quoteResult: { quotes: { BTC: quote("BTC", 100), ETH: quote("ETH", 200) }, missingSymbols: [], errors: [], updatedAt: 1_000 },
    invalidRuleTokens: [],
    isLoading: false,
    now: 12_000,
  });

  expect(model.title).toBe("BTC 100.00 · ETH 200.00");
  expect(model.items.map((item) => item.title)).toEqual(["BTC: 100.00", "ETH: 200.00"]);
});
