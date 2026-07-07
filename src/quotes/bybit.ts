import { getInstrumentName } from "#/constants";
import type { Quote } from "#/types";
import { fetchJsonWithRetry } from "./fetchWithRetry";

const LINEAR_TICKER_URL = "https://api.bytick.com/v5/market/tickers?category=linear";

type BybitTicker = {
  symbol: string;
  lastPrice: string;
  highPrice24h: string;
  lowPrice24h: string;
};

type BybitTickersResponse = {
  retCode: number;
  retMsg?: string;
  result?: { list?: unknown[] };
};

export async function fetchBybitLinearQuotes(symbols: string[]): Promise<Record<string, Quote>> {
  const data = await fetchJsonWithRetry<BybitTickersResponse>(LINEAR_TICKER_URL, { attempts: 1, timeoutMs: 8000, useCurl: true });
  if (data.retCode !== 0) {
    throw new Error(data.retMsg || `Bybit returned retCode ${data.retCode}`);
  }

  const targetSymbols = new Set(symbols.map((symbol) => `${symbol}USDT`));
  const result = data.result;
  const list = result && Array.isArray(result.list) ? result.list : [];
  const updatedAt = Date.now();
  const quotes: Record<string, Quote> = {};

  for (const item of list) {
    if (!isBybitTicker(item) || !targetSymbols.has(item.symbol)) {
      continue;
    }
    const symbol = item.symbol.replace(/USDT$/, "");
    quotes[symbol] = {
      symbol,
      name: getInstrumentName(symbol),
      price: Number(item.lastPrice),
      high24h: Number(item.highPrice24h),
      low24h: Number(item.lowPrice24h),
      source: "Bybit linear (USDT)",
      updatedAt,
    };
  }

  return quotes;
}

function isBybitTicker(value: unknown): value is BybitTicker {
  if (!value || typeof value !== "object") {
    return false;
  }
  const ticker = value as Record<string, unknown>;
  return (
    typeof ticker.symbol === "string" &&
    typeof ticker.lastPrice === "string" &&
    typeof ticker.highPrice24h === "string" &&
    typeof ticker.lowPrice24h === "string"
  );
}
