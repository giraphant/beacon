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
      {
        name: "Bybit",
        fetchQuotes: async () => {
          throw new Error("down");
        },
      },
      { name: "Binance", fetchQuotes: async () => ({ BTC: quote("BTC", "Binance") }) },
    ];

    const result = await fetchQuotesFromSources(["BTC", "SOL"], sources, 10_000);

    expect(result.quotes.BTC.source).toBe("Binance");
    expect(result.missingSymbols).toEqual(["SOL"]);
    expect(result.errors).toEqual(["Bybit: down"]);
  });
});
