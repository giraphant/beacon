import { getInstrumentName } from "#/constants";
import type { Quote } from "#/types";
import { fetchJsonWithRetry } from "./fetchWithRetry";

const SPOT_TICKER_URL = "https://api.binance.com/api/v3/ticker/24hr";

type BinanceTicker = {
  symbol: string;
  lastPrice: string;
  highPrice: string;
  lowPrice: string;
};

export async function fetchBinanceSpotQuotes(symbols: string[]): Promise<Record<string, Quote>> {
  const data = await fetchJsonWithRetry<unknown>(getTickersUrl(symbols), { attempts: 1, timeoutMs: 3500 });
  if (!Array.isArray(data)) {
    return {};
  }

  const targetSymbols = new Set(symbols.map((symbol) => `${symbol}USDT`));
  const updatedAt = Date.now();
  const quotes: Record<string, Quote> = {};

  for (const item of data) {
    if (!isBinanceTicker(item) || !targetSymbols.has(item.symbol)) {
      continue;
    }
    const symbol = item.symbol.replace(/USDT$/, "");
    quotes[symbol] = {
      symbol,
      name: getInstrumentName(symbol),
      price: Number(item.lastPrice),
      high24h: Number(item.highPrice),
      low24h: Number(item.lowPrice),
      source: "Binance spot (USDT)",
      updatedAt,
    };
  }

  return quotes;
}

function isBinanceTicker(value: unknown): value is BinanceTicker {
  if (!value || typeof value !== "object") {
    return false;
  }
  const ticker = value as Record<string, unknown>;
  return (
    typeof ticker.symbol === "string" &&
    typeof ticker.lastPrice === "string" &&
    typeof ticker.highPrice === "string" &&
    typeof ticker.lowPrice === "string"
  );
}

function getTickersUrl(symbols: string[]) {
  const pairSymbols = JSON.stringify(symbols.map((symbol) => `${symbol}USDT`));
  return `${SPOT_TICKER_URL}?symbols=${encodeURIComponent(pairSymbols)}&type=MINI`;
}
