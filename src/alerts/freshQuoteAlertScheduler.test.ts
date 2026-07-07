import type { AlertRule, Quote } from "#/types";
import { createFreshQuoteAlertScheduler } from "./freshQuoteAlertScheduler";

const btcRule: AlertRule = { symbol: "BTC", thresholdPercent: 2, enabled: true };
const ethRule: AlertRule = { symbol: "ETH", thresholdPercent: 1, enabled: true };

function quote(symbol: string, price: number, updatedAt: number): Quote {
  return { symbol, name: symbol, price, source: "test", updatedAt };
}

describe("fresh quote alert scheduler", () => {
  test("queues a second fresh quote result submitted while one run is in flight", async () => {
    const processed: Array<Record<string, Quote>> = [];
    let finishFirstRun: (() => void) | undefined;

    const scheduler = createFreshQuoteAlertScheduler({
      runAlerts: async ({ quotes }) => {
        processed.push(quotes);
        if (processed.length === 1) {
          await new Promise<void>((resolve) => {
            finishFirstRun = resolve;
          });
        }
      },
    });

    scheduler.submitFreshQuoteResult({
      quotes: { BTC: quote("BTC", 100, 1) },
      rules: [btcRule],
      fetchRuleSignature: "BTC:2",
      currentRuleSignature: "BTC:2",
      fetchQuoteSymbolSignature: "BTC",
      currentQuoteSymbolSignature: "BTC",
      now: 10,
    });

    scheduler.submitFreshQuoteResult({
      quotes: { BTC: quote("BTC", 110, 2) },
      rules: [btcRule],
      fetchRuleSignature: "BTC:2",
      currentRuleSignature: "BTC:2",
      fetchQuoteSymbolSignature: "BTC",
      currentQuoteSymbolSignature: "BTC",
      now: 20,
    });

    expect(processed).toHaveLength(1);
    finishFirstRun?.();
    await scheduler.waitForIdle();

    expect(processed).toHaveLength(2);
    expect(processed[0].BTC.price).toBe(100);
    expect(processed[1].BTC.price).toBe(110);
  });

  test("does not run alerts for old data after rules change without a fresh quote result", async () => {
    const processedRules: AlertRule[][] = [];
    const scheduler = createFreshQuoteAlertScheduler({
      runAlerts: async ({ rules }) => {
        processedRules.push(rules);
      },
    });

    scheduler.submitFreshQuoteResult({
      quotes: { BTC: quote("BTC", 100, 1) },
      rules: [btcRule],
      fetchRuleSignature: "BTC:2",
      currentRuleSignature: "BTC:2",
      fetchQuoteSymbolSignature: "BTC",
      currentQuoteSymbolSignature: "BTC",
      now: 10,
    });
    await scheduler.waitForIdle();

    scheduler.submitFreshQuoteResult({
      quotes: { BTC: quote("BTC", 100, 1) },
      rules: [ethRule],
      fetchRuleSignature: "BTC:2",
      currentRuleSignature: "ETH:1",
      fetchQuoteSymbolSignature: "BTC",
      currentQuoteSymbolSignature: "BTC,ETH",
      now: 20,
    });
    await scheduler.waitForIdle();

    expect(processedRules).toHaveLength(1);
    expect(processedRules[0]).toEqual([btcRule]);
  });
});
