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
  const data = await fetchJsonWithRetry<unknown>(getTickersUrl(symbols), { attempts: 1, timeoutMs: 3500, useCurl: true });
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
    const price = Number(item.lastPrice);
    const high24h = Number(item.highPrice);
    const low24h = Number(item.lowPrice);
    if (!isPositiveFinite(price) || !isPositiveFinite(high24h) || !isPositiveFinite(low24h)) {
      continue;
    }
    const symbol = item.symbol.replace(/USDT$/, "");
    quotes[symbol] = {
      symbol,
      name: getInstrumentName(symbol),
      price,
      high24h,
      low24h,
      source: "Binance spot (USDT)",
      updatedAt,
    };
  }

  return quotes;
}

function isPositiveFinite(value: number) {
  return Number.isFinite(value) && value > 0;
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
