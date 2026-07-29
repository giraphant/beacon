import type { IntegerAlertRule, IntegerAlertState, Quote } from "#/types";
import { evaluateIntegerAlert } from "./evaluateIntegerAlert";

const rule: IntegerAlertRule = { symbol: "BTC", step: 1000, enabled: true };
const quote = (price: number): Quote => ({
  symbol: "BTC",
  name: "Bitcoin",
  price,
  source: "Test",
  updatedAt: 1_000,
});
const state = (lastBucket: number, lastPrice: number): IntegerAlertState => ({ symbol: "BTC", lastBucket, lastPrice });

describe("evaluateIntegerAlert", () => {
  it("initializes the current bucket on first quote without alerting", () => {
    expect(evaluateIntegerAlert(rule, quote(65_820), undefined, 10_000)).toEqual({
      kind: "initialize",
      nextState: { symbol: "BTC", lastBucket: 65, lastPrice: 65_820 },
    });
  });

  it("does nothing while price stays in the same bucket", () => {
    expect(evaluateIntegerAlert(rule, quote(65_999), state(65, 65_820), 10_000)).toEqual({ kind: "none" });
  });

  it("triggers on upward boundary crossing", () => {
    const result = evaluateIntegerAlert(rule, quote(66_120), state(65, 65_820), 10_000);

    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.nextState).toEqual({
      symbol: "BTC",
      lastBucket: 66,
      lastPrice: 66_120,
      lastTriggeredAt: 10_000,
      lastTriggeredPrice: 66_120,
    });
    expect(result.notification.title).toBe("BTC crossed above $66,000");
    expect(result.notification.crossedSteps).toBe(1);
  });

  it("triggers on downward boundary crossing", () => {
    const result = evaluateIntegerAlert(rule, quote(64_900), state(65, 65_120), 10_000);

    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.title).toBe("BTC crossed below $65,000");
    expect(result.notification.crossedSteps).toBe(1);
  });

  it("updates state without notifying when the same boundary is in cooldown", () => {
    const result = evaluateIntegerAlert(
      rule,
      quote(64_900),
      { ...state(65, 65_120), lastTriggeredBoundaryRanges: [{ startBucket: 65, endBucket: 65, triggeredAt: 9_500 }] },
      10_000,
      60_000
    );

    expect(result).toEqual({
      kind: "update",
      nextState: {
        symbol: "BTC",
        lastBucket: 64,
        lastPrice: 64_900,
        lastTriggeredBoundaryRanges: [{ startBucket: 65, endBucket: 65, triggeredAt: 9_500 }],
      },
    });
  });

  it("still notifies for a different boundary during cooldown", () => {
    const result = evaluateIntegerAlert(
      rule,
      quote(66_120),
      { ...state(65, 65_820), lastTriggeredBoundaryRanges: [{ startBucket: 65, endBucket: 65, triggeredAt: 9_500 }] },
      10_000,
      60_000
    );

    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.title).toBe("BTC crossed above $66,000");
  });

  it("notifies for same boundary when cooldown is disabled", () => {
    const result = evaluateIntegerAlert(
      rule,
      quote(64_900),
      { ...state(65, 65_120), lastTriggeredBoundaryRanges: [{ startBucket: 65, endBucket: 65, triggeredAt: 9_500 }] },
      10_000,
      0
    );

    expect(result.kind).toBe("trigger");
  });

  it("summarizes multiple crossed buckets in one notification", () => {
    const result = evaluateIntegerAlert(rule, quote(68_200), state(65, 65_820), 10_000, 60_000);

    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.message).toBe("$65,820 → $68,200, crossed 3 × $1,000 steps");
    expect(result.notification.crossedSteps).toBe(3);
    expect(result.nextState.lastTriggeredBoundaryRanges).toEqual([
      { startBucket: 66, endBucket: 68, triggeredAt: 10_000 },
    ]);
  });

  it("cools down all boundaries from a previous multi-step notification", () => {
    const result = evaluateIntegerAlert(
      rule,
      quote(66_900),
      {
        ...state(68, 68_200),
        lastTriggeredBoundaryRanges: [{ startBucket: 66, endBucket: 68, triggeredAt: 10_000 }],
      },
      20_000,
      60_000
    );

    expect(result.kind).toBe("update");
  });

  it("titles a mixed cooled and fresh multi-step drop with the fresh boundary", () => {
    const result = evaluateIntegerAlert(
      rule,
      quote(64_900),
      { ...state(66, 66_200), lastTriggeredBoundaryRanges: [{ startBucket: 66, endBucket: 66, triggeredAt: 10_000 }] },
      20_000,
      60_000
    );

    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.title).toBe("BTC crossed below $65,000");
  });

  it("handles decimal steps without missing exact-looking boundaries", () => {
    const jupRule: IntegerAlertRule = { symbol: "JUP", step: 0.05, enabled: true };
    const jupQuote: Quote = { ...quote(0.3), symbol: "JUP", name: "Jupiter" };
    const jupState: IntegerAlertState = { symbol: "JUP", lastBucket: 5, lastPrice: 0.25 };

    const result = evaluateIntegerAlert(jupRule, jupQuote, jupState, 10_000);

    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.title).toBe("JUP crossed above $0.3000");
  });

  it("does nothing for invalid quotes and disabled rules", () => {
    expect(evaluateIntegerAlert(rule, quote(Number.NaN), state(65, 65_820), 10_000)).toEqual({ kind: "none" });
    expect(evaluateIntegerAlert({ ...rule, enabled: false }, quote(66_120), state(65, 65_820), 10_000)).toEqual({
      kind: "none",
    });
  });
});
