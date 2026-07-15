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
});
