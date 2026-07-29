import type { AlertNotification, IntegerAlertRule, IntegerAlertState, Quote } from "#/types";
import { runIntegerAlerts } from "./runIntegerAlerts";

const quote = (symbol: string, price: number): Quote => ({
  symbol,
  name: symbol,
  price,
  source: "Test",
  updatedAt: 1_000,
});
const rule = (symbol: string, step: number): IntegerAlertRule => ({ symbol, step, enabled: true });

describe("runIntegerAlerts", () => {
  it("creates bucket states without notifying", async () => {
    const saved: IntegerAlertState[] = [];
    const notifications: AlertNotification[] = [];

    const result = await runIntegerAlerts({
      rules: [rule("BTC", 1000)],
      quotes: { BTC: quote("BTC", 65_820) },
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
    expect(saved).toEqual([{ symbol: "BTC", lastBucket: 65, lastPrice: 65_820 }]);
    expect(notifications).toEqual([]);
  });

  it("saves next state only after notification succeeds", async () => {
    const saved: IntegerAlertState[] = [];
    const notifications: AlertNotification[] = [];

    const result = await runIntegerAlerts({
      rules: [rule("BTC", 1000)],
      quotes: { BTC: quote("BTC", 66_120) },
      now: 10_000,
      getState: async () => ({ symbol: "BTC", lastBucket: 65, lastPrice: 65_820 }),
      saveState: async (state) => {
        saved.push(state);
      },
      notify: async (notification) => {
        notifications.push(notification);
      },
    });

    expect(result).toEqual({ initialized: 0, triggered: 1, skipped: 0, failed: 0 });
    expect(notifications).toHaveLength(1);
    expect(saved).toEqual([
      { symbol: "BTC", lastBucket: 66, lastPrice: 66_120, lastTriggeredAt: 10_000, lastTriggeredPrice: 66_120 },
    ]);
  });

  it("does not save trigger state when notification fails", async () => {
    const saved: IntegerAlertState[] = [];

    const result = await runIntegerAlerts({
      rules: [rule("BTC", 1000)],
      quotes: { BTC: quote("BTC", 66_120) },
      now: 10_000,
      getState: async () => ({ symbol: "BTC", lastBucket: 65, lastPrice: 65_820 }),
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

  it("saves cooldown updates without notifying", async () => {
    const saved: IntegerAlertState[] = [];
    const notifications: AlertNotification[] = [];

    const result = await runIntegerAlerts({
      rules: [rule("BTC", 1000)],
      quotes: { BTC: quote("BTC", 64_900) },
      now: 10_000,
      integerAlertCooldownMs: 60_000,
      getState: async () => ({
        symbol: "BTC",
        lastBucket: 65,
        lastPrice: 65_120,
        lastTriggeredBoundaryRanges: [{ startBucket: 65, endBucket: 65, triggeredAt: 9_500 }],
      }),
      saveState: async (state) => {
        saved.push(state);
      },
      notify: async (notification) => {
        notifications.push(notification);
      },
    });

    expect(result).toEqual({ initialized: 0, triggered: 0, skipped: 0, failed: 0 });
    expect(notifications).toEqual([]);
    expect(saved).toEqual([
      {
        symbol: "BTC",
        lastBucket: 64,
        lastPrice: 64_900,
        lastTriggeredBoundaryRanges: [{ startBucket: 65, endBucket: 65, triggeredAt: 9_500 }],
      },
    ]);
  });

  it("uses rule step identity when loading and saving state", async () => {
    const requested: string[] = [];
    const saved: Array<{ state: IntegerAlertState; step: number }> = [];

    await runIntegerAlerts({
      rules: [rule("SOL", 5)],
      quotes: { SOL: quote("SOL", 72) },
      now: 10_000,
      getState: async (symbol, step) => {
        requested.push(`${symbol}:${step}`);
        return undefined;
      },
      saveState: async (state, step) => {
        saved.push({ state, step });
      },
      notify: async () => undefined,
    });

    expect(requested).toEqual(["SOL:5"]);
    expect(saved).toEqual([{ state: { symbol: "SOL", lastBucket: 14, lastPrice: 72 }, step: 5 }]);
  });
});
