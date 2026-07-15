import type { QuoteFetchResult } from "#/quotes/types";

export type TaggedQuoteCacheEntry = {
  sourceSignature: string;
  result: QuoteFetchResult;
};

export function createTaggedQuoteCacheEntry(result: QuoteFetchResult, sourceSignature: string): TaggedQuoteCacheEntry {
  return { sourceSignature, result };
}

export function readTaggedQuoteCache(value: unknown, currentSourceSignature: string): QuoteFetchResult | undefined {
  if (typeof value !== "object" || value === null) {
    return undefined;
  }
  const entry = value as Record<string, unknown>;
  if (typeof entry.sourceSignature !== "string" || typeof entry.result !== "object" || entry.result === null) {
    return undefined;
  }
  if (entry.sourceSignature !== currentSourceSignature) {
    return undefined;
  }
  return isValidQuoteFetchResult(entry.result) ? (entry.result as QuoteFetchResult) : undefined;
}

function isValidQuoteFetchResult(value: object): boolean {
  const result = value as Record<string, unknown>;
  if (typeof result.quotes !== "object" || result.quotes === null || Array.isArray(result.quotes)) {
    return false;
  }
  if (!isStringArray(result.missingSymbols) || !isStringArray(result.errors)) {
    return false;
  }
  if (typeof result.updatedAt !== "number" || !Number.isFinite(result.updatedAt) || result.updatedAt < 0) {
    return false;
  }
  const quotes = result.quotes as Record<string, unknown>;
  return Object.values(quotes).every(isValidQuote);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function isValidQuote(value: unknown): boolean {
  if (!value || typeof value !== "object") {
    return false;
  }
  const quote = value as Record<string, unknown>;
  return (
    typeof quote.symbol === "string" &&
    quote.symbol !== "" &&
    typeof quote.name === "string" &&
    quote.name !== "" &&
    typeof quote.source === "string" &&
    quote.source !== "" &&
    typeof quote.price === "number" &&
    Number.isFinite(quote.price) &&
    quote.price > 0 &&
    typeof quote.updatedAt === "number" &&
    Number.isFinite(quote.updatedAt) &&
    quote.updatedAt >= 0 &&
    isOptionalFiniteNumber(quote.high24h) &&
    isOptionalFiniteNumber(quote.low24h) &&
    isOptionalFiniteNumber(quote.change24h) &&
    (quote.stale === undefined || typeof quote.stale === "boolean")
  );
}

function isOptionalFiniteNumber(value: unknown): boolean {
  return value === undefined || (typeof value === "number" && Number.isFinite(value));
}
