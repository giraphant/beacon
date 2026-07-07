import { fetchJsonWithRetry } from "./fetchWithRetry";
import { fetchBybitLinearQuotes } from "./bybit";

jest.mock("./fetchWithRetry", () => ({ fetchJsonWithRetry: jest.fn() }));

const mockedFetchJsonWithRetry = fetchJsonWithRetry as jest.MockedFunction<typeof fetchJsonWithRetry>;

describe("fetchBybitLinearQuotes", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(Date, "now").mockReturnValue(1234);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("skips tickers with non-finite or non-positive price, high, or low values", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce({ retCode: 0, result: { list: [
          { symbol: "BTCUSDT", lastPrice: "100", highPrice24h: "110", lowPrice24h: "90" },
          { symbol: "ETHUSDT", lastPrice: "NaN", highPrice24h: "210", lowPrice24h: "190" },
          { symbol: "SOLUSDT", lastPrice: "50", highPrice24h: "Infinity", lowPrice24h: "40" },
          { symbol: "DOGEUSDT", lastPrice: "0", highPrice24h: "1", lowPrice24h: "0.1" },
        ] } } as never);

    await expect(fetchBybitLinearQuotes(["BTC", "ETH", "SOL", "DOGE"])).resolves.toEqual({
      BTC: { symbol: "BTC", name: "Bitcoin", price: 100, high24h: 110, low24h: 90, source: "Bybit linear (USDT)", updatedAt: 1234 },
    });
  });
});
