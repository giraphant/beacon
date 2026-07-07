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
      saveState: async (state) => saved.push(state),
      notify: async (notification) => notifications.push(notification),
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
      saveState: async (state) => saved.push(state),
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
      saveState: async (state) => saved.push(state),
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
