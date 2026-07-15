import { fetchJsonWithRetry } from "./fetchWithRetry";
import { fetchBinanceSpotQuotes } from "./binance";

jest.mock("./fetchWithRetry", () => ({ fetchJsonWithRetry: jest.fn() }));

const mockedFetchJsonWithRetry = fetchJsonWithRetry as jest.MockedFunction<typeof fetchJsonWithRetry>;

describe("fetchBinanceSpotQuotes", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Date, "now").mockReturnValue(1234);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("skips tickers with non-finite or non-positive price, high, or low values", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce([
      { symbol: "BTCUSDT", lastPrice: "100", highPrice: "110", lowPrice: "90" },
      { symbol: "ETHUSDT", lastPrice: "NaN", highPrice: "210", lowPrice: "190" },
      { symbol: "SOLUSDT", lastPrice: "50", highPrice: "Infinity", lowPrice: "40" },
      { symbol: "DOGEUSDT", lastPrice: "0", highPrice: "1", lowPrice: "0.1" },
    ] as never);

    await expect(fetchBinanceSpotQuotes(["BTC", "ETH", "SOL", "DOGE"])).resolves.toEqual({
      BTC: {
        symbol: "BTC",
        name: "Bitcoin",
        price: 100,
        high24h: 110,
        low24h: 90,
        source: "Binance spot (USDT)",
        updatedAt: 1234,
      },
    });
  });

  it("requests all tickers without symbols param and filters locally for mixed crypto/equity", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce([
      { symbol: "BTCUSDT", lastPrice: "100", highPrice: "110", lowPrice: "90" },
      { symbol: "ETHUSDT", lastPrice: "200", highPrice: "210", lowPrice: "190" },
    ] as never);

    const result = await fetchBinanceSpotQuotes(["BTC", "NVDA"]);

    const requestedUrl = mockedFetchJsonWithRetry.mock.calls[0][0];
    expect(requestedUrl).not.toContain("symbols=");
    expect(requestedUrl).toContain("type=MINI");
    expect(result.BTC).toEqual({
      symbol: "BTC",
      name: "Bitcoin",
      price: 100,
      high24h: 110,
      low24h: 90,
      source: "Binance spot (USDT)",
      updatedAt: 1234,
    });
  });

  it("rejects a non-array HTTP-200 body as invalid", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce({ code: -1121, msg: "Invalid symbol" } as never);

    await expect(fetchBinanceSpotQuotes(["BTC"])).rejects.toThrow("Binance returned an invalid response");
  });
});
