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
  return entry.result as QuoteFetchResult;
}
