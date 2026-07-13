import { getInstrumentName } from "#/constants";
import type { Quote } from "#/types";

const REQUEST_TIMEOUT_MS = 3_000;

export type QuoteFetchResult = {
  quotes: Record<string, Quote>;
  missingSymbols: string[];
  errors: string[];
  updatedAt: number;
};

type RelayQuote = {
  price: number;
  high24h: number;
  low24h: number;
  source: string;
  updatedAt: number;
  stale: boolean;
};

type RelayResponse = {
  serverTime: number;
  quotes: Record<string, RelayQuote>;
  missingSymbols: string[];
};

class RelayRequestError extends Error {}

export async function fetchRelayQuotes(
  symbols: string[],
  relayUrl: string | undefined,
  relayToken: string | undefined
): Promise<QuoteFetchResult> {
  const url = buildRelayUrl(symbols, relayUrl);
  const token = relayToken?.trim();
  if (!token) {
    throw new RelayRequestError("Relay token is not configured");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
      signal: controller.signal,
    });
    if (!response.ok) {
      throw httpError(response.status);
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new RelayRequestError("Relay returned an invalid response");
    }
    return parseRelayResponse(body);
  } catch (error) {
    if (controller.signal.aborted) {
      throw new RelayRequestError(`Relay request timed out after ${REQUEST_TIMEOUT_MS}ms`);
    }
    if (error instanceof RelayRequestError) {
      throw error;
    }
    throw new RelayRequestError("Relay request failed");
  } finally {
    clearTimeout(timeout);
  }
}

function buildRelayUrl(symbols: string[], relayUrl: string | undefined) {
  const rawUrl = relayUrl?.trim();
  if (!rawUrl) {
    throw new RelayRequestError("Relay URL is not configured");
  }

  let baseUrl: URL;
  try {
    baseUrl = new URL(rawUrl);
  } catch {
    throw new RelayRequestError("Relay URL is invalid");
  }

  const isLocalHttp = baseUrl.protocol === "http:" && isLocalHostname(baseUrl.hostname);
  if (baseUrl.protocol !== "https:" && !isLocalHttp) {
    throw new RelayRequestError("Relay URL must use HTTPS");
  }

  const uniqueSymbols = [...new Set(symbols.map((symbol) => symbol.trim().toUpperCase()).filter(Boolean))];
  const url = new URL("/v1/quotes", baseUrl);
  url.searchParams.set("symbols", uniqueSymbols.join(","));
  return url;
}

function isLocalHostname(hostname: string) {
  return hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1" || hostname === "[::1]";
}

function httpError(status: number) {
  if (status === 401) {
    return new RelayRequestError("Relay authentication failed (401)");
  }
  if (status === 429) {
    return new RelayRequestError("Relay rate limit exceeded (429)");
  }
  if (status === 503) {
    return new RelayRequestError("Relay unavailable (503)");
  }
  return new RelayRequestError(`Relay request failed (${status})`);
}

function parseRelayResponse(value: unknown): QuoteFetchResult {
  if (!isRecord(value) || !isPositiveFinite(value.serverTime) || !isRecord(value.quotes)) {
    throw new RelayRequestError("Relay returned an invalid response");
  }
  if (!Array.isArray(value.missingSymbols) || !value.missingSymbols.every((symbol) => typeof symbol === "string")) {
    throw new RelayRequestError("Relay returned an invalid response");
  }

  const response = value as RelayResponse;
  const quotes: Record<string, Quote> = {};
  for (const [symbol, rawQuote] of Object.entries(response.quotes)) {
    if (!isRelayQuote(rawQuote)) {
      throw new RelayRequestError("Relay returned an invalid response");
    }
    quotes[symbol] = {
      symbol,
      name: getInstrumentName(symbol),
      price: rawQuote.price,
      high24h: rawQuote.high24h,
      low24h: rawQuote.low24h,
      source: rawQuote.source,
      updatedAt: rawQuote.updatedAt,
      stale: rawQuote.stale,
    };
  }

  return {
    quotes,
    missingSymbols: response.missingSymbols,
    errors: [],
    updatedAt: response.serverTime,
  };
}

function isRelayQuote(value: unknown): value is RelayQuote {
  if (!isRecord(value)) {
    return false;
  }
  return (
    isPositiveFinite(value.price) &&
    isPositiveFinite(value.high24h) &&
    isPositiveFinite(value.low24h) &&
    typeof value.source === "string" &&
    value.source.trim().length > 0 &&
    isPositiveFinite(value.updatedAt) &&
    typeof value.stale === "boolean"
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isPositiveFinite(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}
