import { fetchJsonWithRetry } from "./fetchWithRetry";

describe("fetchJsonWithRetry", () => {
  it("uses injected curl runner when fetch fails and curl fallback is enabled", async () => {
    const data = await fetchJsonWithRetry<{ ok: boolean }>("https://example.com/ticker", {
      attempts: 1,
      useCurl: true,
      fetcher: async () => {
        throw new Error("fetch failed");
      },
      curlRunner: async () => ({ status: 200, body: '{"ok":true}' }),
      scutilRunner: async () => "",
    });

    expect(data).toEqual({ ok: true });
  });

  it("throws an HTTP-style error when curl returns a non-2xx status", async () => {
    await expect(
      fetchJsonWithRetry("https://example.com/ticker", {
        attempts: 1,
        useCurl: true,
        fetcher: async () => {
          throw new Error("fetch failed");
        },
        curlRunner: async () => ({ status: 503, body: "Service unavailable" }),
        scutilRunner: async () => "",
      })
    ).rejects.toThrow("Request failed (503 HTTP error): https://example.com/ticker");
  });

  it("derives proxy args from scutil HTTPS proxy output and passes them to curl", async () => {
    const curlCalls: Array<{ url: string; timeoutMs: number; proxyArgs: string[] }> = [];

    await fetchJsonWithRetry("https://example.com/ticker", {
      attempts: 1,
      timeoutMs: 9000,
      useCurl: true,
      fetcher: async () => {
        throw new Error("fetch failed");
      },
      scutilRunner: async () => `
<dictionary> {
  HTTPSEnable : 1
  HTTPSProxy : 127.0.0.1
  HTTPSPort : 6152
}
`,
      curlRunner: async (url, timeoutMs, proxyArgs) => {
        curlCalls.push({ url, timeoutMs, proxyArgs });
        return { status: 200, body: '{"ok":true}' };
      },
    });

    expect(curlCalls).toEqual([
      {
        url: "https://example.com/ticker",
        timeoutMs: 9000,
        proxyArgs: ["--proxy", "http://127.0.0.1:6152"],
      },
    ]);
  });

  it("ignores stale HTTPS proxy host/port when HTTPSEnable is disabled", async () => {
    const curlCalls: Array<{ url: string; timeoutMs: number; proxyArgs: string[] }> = [];

    await fetchJsonWithRetry("https://example.com/ticker", {
      attempts: 1,
      useCurl: true,
      fetcher: async () => {
        throw new Error("fetch failed");
      },
      scutilRunner: async () => `
<dictionary> {
  HTTPSEnable : 0
  HTTPSProxy : 127.0.0.1
  HTTPSPort : 6152
}
`,
      curlRunner: async (url, timeoutMs, proxyArgs) => {
        curlCalls.push({ url, timeoutMs, proxyArgs });
        return { status: 200, body: '{"ok":true}' };
      },
    });

    expect(curlCalls).toEqual([
      {
        url: "https://example.com/ticker",
        timeoutMs: 4500,
        proxyArgs: [],
      },
    ]);
  });

  it("does not invoke curlRunner after fetch failure when useCurl is omitted", async () => {
    const curlCalls: Array<{ url: string; timeoutMs: number; proxyArgs: string[] }> = [];

    await expect(
      fetchJsonWithRetry("https://example.com/ticker", {
        attempts: 1,
        fetcher: async () => {
          throw new Error("fetch failed");
        },
        curlRunner: async (url, timeoutMs, proxyArgs) => {
          curlCalls.push({ url, timeoutMs, proxyArgs });
          return { status: 200, body: '{"ok":true}' };
        },
        scutilRunner: async () => "",
      })
    ).rejects.toThrow("fetch failed");

    expect(curlCalls).toEqual([]);
  });

  it("aborts the native signal and proceeds to curl fallback when headers resolve but response.json() stalls past the timeout", async () => {
    jest.useFakeTimers();

    let receivedSignal: AbortSignal | undefined;
    const fetcher = (_url: string, _timeoutMs: number, signal?: AbortSignal): Promise<Response> => {
      receivedSignal = signal;
      const neverResolvingJson = () => new Promise<never>(() => undefined);
      const res = {
        ok: true,
        status: 200,
        statusText: "OK",
        json: neverResolvingJson,
      } as unknown as Response;
      return Promise.resolve(res);
    };

    const curlCalls: Array<{ url: string; timeoutMs: number }> = [];

    const promise = fetchJsonWithRetry("https://example.com/ticker", {
      attempts: 1,
      timeoutMs: 3000,
      fetcher,
      curlRunner: async (url, timeoutMs) => {
        curlCalls.push({ url, timeoutMs });
        return { status: 200, body: '{"ok":true}' };
      },
      scutilRunner: async () => "",
      useCurl: true,
    });

    // Headers resolve instantly; json() never does. Before the fix the timer
    // was already cleared and this hung forever.
    await jest.advanceTimersByTimeAsync(3000);

    const data = await promise;
    expect(data).toEqual({ ok: true });
    expect(receivedSignal?.aborted).toBe(true);
    expect(curlCalls).toHaveLength(1);

    jest.useRealTimers();
  });

  it("rejects when headers resolve but response.json() stalls past the timeout and no curl fallback is configured", async () => {
    jest.useFakeTimers();

    let receivedSignal: AbortSignal | undefined;
    const fetcher = (_url: string, _timeoutMs: number, signal?: AbortSignal): Promise<Response> => {
      receivedSignal = signal;
      const neverResolvingJson = () => new Promise<never>(() => undefined);
      const res = {
        ok: true,
        status: 200,
        statusText: "OK",
        json: neverResolvingJson,
      } as unknown as Response;
      return Promise.resolve(res);
    };

    const expectation = expect(
      fetchJsonWithRetry("https://example.com/ticker", {
        attempts: 1,
        timeoutMs: 3000,
        fetcher,
      })
    ).rejects.toThrow();

    await jest.advanceTimersByTimeAsync(3000);

    await expectation;
    expect(receivedSignal?.aborted).toBe(true);

    jest.useRealTimers();
  });
});
