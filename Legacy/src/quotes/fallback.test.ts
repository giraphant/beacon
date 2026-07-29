import type { Quote } from "#/types";
import { fetchQuotesFromSources, getQuoteSources, type QuoteSource } from "./fallback";

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

  it("rejects with an aggregate error when every source throws", async () => {
    const sources: QuoteSource[] = [
      {
        name: "Bybit",
        fetchQuotes: async () => {
          throw new Error("bybit down");
        },
      },
      {
        name: "Binance",
        fetchQuotes: async () => {
          throw new Error("binance down");
        },
      },
    ];

    await expect(fetchQuotesFromSources(["BTC"], sources, 10_000)).rejects.toThrow(
      "Bybit: bybit down, Binance: binance down"
    );
  });
});

describe("getQuoteSources", () => {
  it("defaults to Bybit before Binance", () => {
    expect(getQuoteSources(undefined).map((source) => source.name)).toEqual(["Bybit", "Binance"]);
  });

  it("can prefer Binance before Bybit", () => {
    expect(getQuoteSources("Binance").map((source) => source.name)).toEqual(["Binance", "Bybit"]);
  });
});
