import type { Quote } from "#/types";
import { fetchBinanceSpotQuotes } from "./binance";
import { fetchBybitLinearQuotes } from "./bybit";

export type QuoteFetchResult = {
  quotes: Record<string, Quote>;
  missingSymbols: string[];
  errors: string[];
  updatedAt: number;
};

export type QuoteSource = {
  name: string;
  fetchQuotes: (symbols: string[]) => Promise<Record<string, Quote>>;
};

export type PreferredQuoteSource = "Bybit" | "Binance";

const BYBIT_SOURCE: QuoteSource = { name: "Bybit", fetchQuotes: fetchBybitLinearQuotes };
const BINANCE_SOURCE: QuoteSource = { name: "Binance", fetchQuotes: fetchBinanceSpotQuotes };

export function getQuoteSources(preferredSource: PreferredQuoteSource | undefined): QuoteSource[] {
  return preferredSource === "Binance" ? [BINANCE_SOURCE, BYBIT_SOURCE] : [BYBIT_SOURCE, BINANCE_SOURCE];
}

export function fetchQuotesWithFallback(symbols: string[], preferredSource?: PreferredQuoteSource) {
  return fetchQuotesFromSources(symbols, getQuoteSources(preferredSource), Date.now());
}

export async function fetchQuotesFromSources(
  symbols: string[],
  sources: QuoteSource[],
  updatedAt: number
): Promise<QuoteFetchResult> {
  const uniqueSymbols = [...new Set(symbols)];
  const quotes: Record<string, Quote> = {};
  const errors: string[] = [];

  for (const source of sources) {
    const missing = uniqueSymbols.filter((symbol) => !quotes[symbol]);
    if (missing.length === 0) {
      break;
    }

    try {
      const sourceQuotes = await source.fetchQuotes(missing);
      for (const symbol of missing) {
        if (sourceQuotes[symbol] && !quotes[symbol]) {
          quotes[symbol] = sourceQuotes[symbol];
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      errors.push(`${source.name}: ${message}`);
    }
  }

  return {
    quotes,
    missingSymbols: uniqueSymbols.filter((symbol) => !quotes[symbol]),
    errors,
    updatedAt,
  };
}
