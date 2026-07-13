import { fetchRelayQuotes } from "./relay";

const originalFetch = global.fetch;
const fetchMock = jest.fn();
const token = "test-relay-token-value";

function response(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response;
}

const relayResponse = {
  serverTime: 10_000,
  quotes: {
    BTC: {
      price: 62_000,
      high24h: 63_000,
      low24h: 60_000,
      source: "bybit-linear",
      updatedAt: 9_999,
      stale: false,
    },
  },
  missingSymbols: ["UNKNOWN"],
};

describe("fetchRelayQuotes", () => {
  beforeEach(() => {
    jest.useRealTimers();
    fetchMock.mockReset();
    global.fetch = fetchMock as typeof fetch;
  });

  afterAll(() => {
    global.fetch = originalFetch;
  });

  it("makes one authenticated request and maps the relay response", async () => {
    fetchMock.mockResolvedValueOnce(response(relayResponse));

    await expect(fetchRelayQuotes(["BTC", "BTC", "UNKNOWN"], "https://relay.example.com/base", token)).resolves.toEqual(
      {
        quotes: {
          BTC: {
            symbol: "BTC",
            name: "Bitcoin",
            price: 62_000,
            high24h: 63_000,
            low24h: 60_000,
            source: "bybit-linear",
            updatedAt: 9_999,
            stale: false,
          },
        },
        missingSymbols: ["UNKNOWN"],
        errors: [],
        updatedAt: 10_000,
      }
    );

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [requestUrl, options] = fetchMock.mock.calls[0] as [URL, RequestInit];
    const url = new URL(requestUrl);
    expect(url.origin + url.pathname).toBe("https://relay.example.com/v1/quotes");
    expect(url.searchParams.get("symbols")).toBe("BTC,UNKNOWN");
    expect(url.toString()).not.toContain(token);
    expect(options.method).toBe("GET");
    expect(options.headers).toEqual({ Authorization: `Bearer ${token}` });
  });

  it.each([
    [undefined, token, "Relay URL is not configured"],
    ["https://relay.example.com", undefined, "Relay token is not configured"],
    ["not a url", token, "Relay URL is invalid"],
    ["http://relay.example.com", token, "Relay URL must use HTTPS"],
  ])("rejects invalid configuration before fetching", async (relayUrl, relayToken, message) => {
    await expect(fetchRelayQuotes(["BTC"], relayUrl, relayToken)).rejects.toThrow(message);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("allows HTTP for local development", async () => {
    fetchMock.mockResolvedValueOnce(response(relayResponse));

    await fetchRelayQuotes(["BTC"], "http://127.0.0.1:18765", token);

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it.each([
    [401, "Relay authentication failed (401)"],
    [429, "Relay rate limit exceeded (429)"],
    [503, "Relay unavailable (503)"],
  ])("reports status %i without exposing the token", async (status, message) => {
    fetchMock.mockResolvedValueOnce(response({}, status));

    const request = fetchRelayQuotes(["BTC"], "https://relay.example.com", token);
    await expect(request).rejects.toThrow(message);
    await expect(request).rejects.not.toThrow(token);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("aborts after three seconds without retrying", async () => {
    jest.useFakeTimers();
    fetchMock.mockImplementationOnce(
      (_url: URL, options: RequestInit) =>
        new Promise((_resolve, reject) => {
          options.signal?.addEventListener("abort", () => reject(new Error("aborted")));
        })
    );

    const request = fetchRelayQuotes(["BTC"], "https://relay.example.com", token);
    jest.advanceTimersByTime(3_000);

    await expect(request).rejects.toThrow("Relay request timed out after 3000ms");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("rejects malformed quote data instead of caching it", async () => {
    fetchMock.mockResolvedValueOnce(
      response({
        ...relayResponse,
        quotes: { BTC: { ...relayResponse.quotes.BTC, stale: "false" } },
      })
    );

    await expect(fetchRelayQuotes(["BTC"], "https://relay.example.com", token)).rejects.toThrow(
      "Relay returned an invalid response"
    );
  });
});
