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
