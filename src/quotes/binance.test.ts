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
      BTC: { symbol: "BTC", name: "Bitcoin", price: 100, high24h: 110, low24h: 90, source: "Binance spot (USDT)", updatedAt: 1234 },
    });
  });
});
