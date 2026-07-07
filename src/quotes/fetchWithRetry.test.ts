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
});
