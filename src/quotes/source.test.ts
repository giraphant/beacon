import { fetchQuotesWithFallback } from "./fallback";
import { fetchRelayQuotes } from "./relay";
import { createQuoteSourceSignature, fetchQuotesForSource } from "./source";

jest.mock("./fallback", () => ({ fetchQuotesWithFallback: jest.fn() }));
jest.mock("./relay", () => ({ fetchRelayQuotes: jest.fn() }));

const directResult = { quotes: {}, missingSymbols: [], errors: [], updatedAt: 1 };
const relayResult = { quotes: {}, missingSymbols: [], errors: [], updatedAt: 2 };

const fallbackMock = fetchQuotesWithFallback as jest.MockedFunction<typeof fetchQuotesWithFallback>;
const relayMock = fetchRelayQuotes as jest.MockedFunction<typeof fetchRelayQuotes>;

describe("quote source dispatch", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    fallbackMock.mockResolvedValue(directResult);
    relayMock.mockResolvedValue(relayResult);
  });

  it.each(["Bybit", "Binance"] as const)("routes %s through direct fallback", async (source) => {
    await expect(fetchQuotesForSource(["BTC"], source, "https://relay.example.com", "secret")).resolves.toBe(
      directResult
    );
    expect(fallbackMock).toHaveBeenCalledWith(["BTC"], source);
    expect(relayMock).not.toHaveBeenCalled();
  });

  it("routes Relay through exactly one relay call", async () => {
    await expect(fetchQuotesForSource(["BTC"], "Relay", "https://relay.example.com", "secret")).resolves.toBe(
      relayResult
    );
    expect(relayMock).toHaveBeenCalledTimes(1);
    expect(relayMock).toHaveBeenCalledWith(["BTC"], "https://relay.example.com", "secret");
    expect(fallbackMock).not.toHaveBeenCalled();
  });

  it("keys direct requests only by source and Relay requests by URL", () => {
    expect(createQuoteSourceSignature("Bybit", "https://unused.example.com")).toBe("Bybit");
    expect(createQuoteSourceSignature("Relay", " https://relay.example.com ")).toBe("Relay:https://relay.example.com");
  });
});
