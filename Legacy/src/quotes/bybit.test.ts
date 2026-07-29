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
    mockedFetchJsonWithRetry.mockResolvedValueOnce({
      retCode: 0,
      result: {
        list: [
          { symbol: "BTCUSDT", lastPrice: "100", highPrice24h: "110", lowPrice24h: "90" },
          { symbol: "ETHUSDT", lastPrice: "NaN", highPrice24h: "210", lowPrice24h: "190" },
          { symbol: "SOLUSDT", lastPrice: "50", highPrice24h: "Infinity", lowPrice24h: "40" },
          { symbol: "DOGEUSDT", lastPrice: "0", highPrice24h: "1", lowPrice24h: "0.1" },
        ],
      },
    } as never);

    await expect(fetchBybitLinearQuotes(["BTC", "ETH", "SOL", "DOGE"])).resolves.toEqual({
      BTC: {
        symbol: "BTC",
        name: "Bitcoin",
        price: 100,
        high24h: 110,
        low24h: 90,
        source: "Bybit linear (USDT)",
        updatedAt: 1234,
      },
    });
  });

  it("accepts a valid empty list array", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce({ retCode: 0, result: { list: [] } } as never);

    await expect(fetchBybitLinearQuotes(["BTC"])).resolves.toEqual({});
  });

  it("rejects retCode 0 with missing result", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce({ retCode: 0 } as never);

    await expect(fetchBybitLinearQuotes(["BTC"])).rejects.toThrow("Bybit returned an invalid response");
  });

  it("rejects retCode 0 with missing list", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce({ retCode: 0, result: {} } as never);

    await expect(fetchBybitLinearQuotes(["BTC"])).rejects.toThrow("Bybit returned an invalid response");
  });

  it("rejects retCode 0 with non-array list", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce({ retCode: 0, result: { list: "not-array" } } as never);

    await expect(fetchBybitLinearQuotes(["BTC"])).rejects.toThrow("Bybit returned an invalid response");
  });

  it("still throws on non-zero retCode", async () => {
    mockedFetchJsonWithRetry.mockResolvedValueOnce({ retCode: 10001, retMsg: "params error" } as never);

    await expect(fetchBybitLinearQuotes(["BTC"])).rejects.toThrow("params error");
  });
});
