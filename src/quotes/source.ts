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
