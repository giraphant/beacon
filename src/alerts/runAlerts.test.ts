import type { AlertNotification, AlertRule, AlertState, Quote } from "#/types";
import { runAlerts } from "./runAlerts";

const quote = (symbol: string, price: number): Quote => ({ symbol, name: symbol, price, source: "Test", updatedAt: 1_000 });
const rule = (symbol: string, thresholdPercent: number): AlertRule => ({ symbol, thresholdPercent, enabled: true });

describe("runAlerts", () => {
  it("creates baseline states without notifying", async () => {
    const saved: AlertState[] = [];
    const notifications: AlertNotification[] = [];

    const result = await runAlerts({
      rules: [rule("BTC", 1)],
      quotes: { BTC: quote("BTC", 100) },
      now: 10_000,
      getState: async () => undefined,
      saveState: async (state) => {
        saved.push(state);
      },
      notify: async (notification) => {
        notifications.push(notification);
      },
    });

    expect(result).toEqual({ initialized: 1, triggered: 0, skipped: 0, failed: 0 });
    expect(saved).toEqual([{ symbol: "BTC", lastBaselinePrice: 100 }]);
    expect(notifications).toEqual([]);
  });

  it("saves next state only after notification succeeds", async () => {
    const saved: AlertState[] = [];

    const result = await runAlerts({
      rules: [rule("BTC", 1)],
      quotes: { BTC: quote("BTC", 102) },
      now: 10_000,
      getState: async () => ({ symbol: "BTC", lastBaselinePrice: 100 }),
      saveState: async (state) => {
        saved.push(state);
      },
      notify: async () => undefined,
    });

    expect(result).toEqual({ initialized: 0, triggered: 1, skipped: 0, failed: 0 });
    expect(saved).toEqual([{ symbol: "BTC", lastBaselinePrice: 102, lastTriggeredAt: 10_000, lastTriggeredPrice: 102 }]);
  });

  it("does not save trigger state when notification fails", async () => {
    const saved: AlertState[] = [];

    const result = await runAlerts({
      rules: [rule("BTC", 1)],
      quotes: { BTC: quote("BTC", 102) },
      now: 10_000,
      getState: async () => ({ symbol: "BTC", lastBaselinePrice: 100 }),
      saveState: async (state) => {
        saved.push(state);
      },
      notify: async () => {
        throw new Error("notification failed");
      },
    });

    expect(result).toEqual({ initialized: 0, triggered: 0, skipped: 0, failed: 1 });
    expect(saved).toEqual([]);
  });

  it("skips rules without quotes", async () => {
    const result = await runAlerts({
      rules: [rule("BTC", 1)],
      quotes: {},
      now: 10_000,
      getState: async () => undefined,
      saveState: async () => undefined,
      notify: async () => undefined,
    });

    expect(result).toEqual({ initialized: 0, triggered: 0, skipped: 1, failed: 0 });
  });
});


it("uses rule identity when loading and saving state", async () => {
  const requested: string[] = [];
  const saved: Array<{ state: AlertState; thresholdPercent: number }> = [];

  await runAlerts({
    rules: [rule("BTC", 2)],
    quotes: { BTC: quote("BTC", 100) },
    now: 10_000,
    getState: async (symbol, thresholdPercent) => {
      requested.push(`${symbol}:${thresholdPercent}`);
      return undefined;
    },
    saveState: async (state, thresholdPercent) => {
      saved.push({ state, thresholdPercent });
    },
    notify: async () => undefined,
  });

  expect(requested).toEqual(["BTC:2"]);
  expect(saved).toEqual([{ state: { symbol: "BTC", lastBaselinePrice: 100 }, thresholdPercent: 2 }]);
});

it("continues evaluating later rules when state load or initialization save fails", async () => {
  const saved: AlertState[] = [];

  const result = await runAlerts({
    rules: [rule("BTC", 1), rule("ETH", 1), rule("SOL", 1)],
    quotes: { BTC: quote("BTC", 100), ETH: quote("ETH", 200), SOL: quote("SOL", 300) },
    now: 10_000,
    getState: async (symbol) => {
      if (symbol === "BTC") throw new Error("load failed");
      return undefined;
    },
    saveState: async (state) => {
      if (state.symbol === "ETH") throw new Error("save failed");
      saved.push(state);
    },
    notify: async () => undefined,
  });

  expect(result).toEqual({ initialized: 1, triggered: 0, skipped: 0, failed: 2 });
  expect(saved).toEqual([{ symbol: "SOL", lastBaselinePrice: 300 }]);
});
