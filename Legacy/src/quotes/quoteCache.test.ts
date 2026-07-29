import type { QuoteFetchResult } from "#/quotes/types";
import { createTaggedQuoteCacheEntry, readTaggedQuoteCache } from "./quoteCache";

const result: QuoteFetchResult = {
  quotes: {},
  missingSymbols: [],
  errors: [],
  updatedAt: 1_000,
};

describe("readTaggedQuoteCache", () => {
  it("returns the result when source signature matches", () => {
    const entry = createTaggedQuoteCacheEntry(result, "Bybit");
    expect(readTaggedQuoteCache(entry, "Bybit")).toBe(result);
  });

  it("returns undefined when source signature mismatches", () => {
    const entry = createTaggedQuoteCacheEntry(result, "Bybit");
    expect(readTaggedQuoteCache(entry, "Relay:https://relay.example.com")).toBeUndefined();
  });

  it("returns undefined for legacy untagged QuoteFetchResult", () => {
    expect(readTaggedQuoteCache(result, "Bybit")).toBeUndefined();
  });

  it("returns undefined for malformed values", () => {
    expect(readTaggedQuoteCache(null, "Bybit")).toBeUndefined();
    expect(readTaggedQuoteCache(undefined, "Bybit")).toBeUndefined();
    expect(readTaggedQuoteCache("not-an-object", "Bybit")).toBeUndefined();
    expect(readTaggedQuoteCache({ foo: "bar" }, "Bybit")).toBeUndefined();
    expect(readTaggedQuoteCache({ sourceSignature: "Bybit" }, "Bybit")).toBeUndefined();
  });

  it("returns undefined when the nested result envelope is empty or missing required fields", () => {
    expect(readTaggedQuoteCache({ sourceSignature: "Bybit", result: {} }, "Bybit")).toBeUndefined();
    expect(
      readTaggedQuoteCache(
        { sourceSignature: "Bybit", result: { quotes: {}, missingSymbols: [], errors: [] } },
        "Bybit"
      )
    ).toBeUndefined();
    expect(
      readTaggedQuoteCache(
        {
          sourceSignature: "Bybit",
          result: { quotes: "not-object", missingSymbols: [], errors: [], updatedAt: 1 },
        },
        "Bybit"
      )
    ).toBeUndefined();
    expect(
      readTaggedQuoteCache(
        {
          sourceSignature: "Bybit",
          result: { quotes: {}, missingSymbols: "not-array", errors: [], updatedAt: 1 },
        },
        "Bybit"
      )
    ).toBeUndefined();
    expect(
      readTaggedQuoteCache(
        {
          sourceSignature: "Bybit",
          result: { quotes: {}, missingSymbols: [], errors: [123], updatedAt: 1 },
        },
        "Bybit"
      )
    ).toBeUndefined();
    expect(
      readTaggedQuoteCache(
        {
          sourceSignature: "Bybit",
          result: { quotes: {}, missingSymbols: [], errors: [], updatedAt: -1 },
        },
        "Bybit"
      )
    ).toBeUndefined();
    expect(
      readTaggedQuoteCache(
        {
          sourceSignature: "Bybit",
          result: { quotes: {}, missingSymbols: [], errors: [], updatedAt: Infinity },
        },
        "Bybit"
      )
    ).toBeUndefined();
  });

  it("returns undefined when the nested result contains a malformed quote", () => {
    expect(
      readTaggedQuoteCache(
        {
          sourceSignature: "Bybit",
          result: {
            quotes: { BTC: { symbol: "", name: "Bitcoin", price: 100, source: "Bybit", updatedAt: 1 } },
            missingSymbols: [],
            errors: [],
            updatedAt: 1,
          },
        },
        "Bybit"
      )
    ).toBeUndefined();

    expect(
      readTaggedQuoteCache(
        {
          sourceSignature: "Bybit",
          result: {
            quotes: { BTC: { symbol: "BTC", name: "Bitcoin", price: -5, source: "Bybit", updatedAt: 1 } },
            missingSymbols: [],
            errors: [],
            updatedAt: 1,
          },
        },
        "Bybit"
      )
    ).toBeUndefined();

    expect(
      readTaggedQuoteCache(
        {
          sourceSignature: "Bybit",
          result: {
            quotes: {
              BTC: {
                symbol: "BTC",
                name: "Bitcoin",
                price: 100,
                source: "Bybit",
                updatedAt: 1,
                high24h: "not-a-number",
              },
            },
            missingSymbols: [],
            errors: [],
            updatedAt: 1,
          },
        },
        "Bybit"
      )
    ).toBeUndefined();
  });
});
