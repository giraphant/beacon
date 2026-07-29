import type { AlertRule, AlertState, Quote } from "#/types";
import { evaluateAlert } from "./evaluateAlert";

const rule: AlertRule = { symbol: "BTC", thresholdPercent: 1, enabled: true };
const quote = (price: number): Quote => ({
  symbol: "BTC",
  name: "Bitcoin",
  price,
  source: "Test",
  updatedAt: 1_000,
});
const state = (lastBaselinePrice: number): AlertState => ({ symbol: "BTC", lastBaselinePrice });

describe("evaluateAlert", () => {
  it("initializes baseline on first quote without alerting", () => {
    expect(evaluateAlert(rule, quote(100), undefined, 10_000)).toEqual({
      kind: "initialize",
      nextState: { symbol: "BTC", lastBaselinePrice: 100 },
    });
  });

  it("does nothing below threshold", () => {
    expect(evaluateAlert(rule, quote(100.5), state(100), 10_000)).toEqual({ kind: "none" });
  });

  it("triggers on upward threshold movement", () => {
    const result = evaluateAlert(rule, quote(101), state(100), 10_000);
    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.nextState).toEqual({
      symbol: "BTC",
      lastBaselinePrice: 101,
      lastTriggeredAt: 10_000,
      lastTriggeredPrice: 101,
    });
    expect(result.notification.title).toBe("BTC rose 1.00%");
    expect(result.notification.crossedSteps).toBe(1);
  });

  it("triggers on downward threshold movement", () => {
    const result = evaluateAlert(rule, quote(98), state(100), 10_000);
    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.title).toBe("BTC fell 2.00%");
    expect(result.notification.crossedSteps).toBe(2);
  });

  it("summarizes multiple crossed steps in one notification", () => {
    const result = evaluateAlert(rule, quote(103.2), state(100), 10_000);
    expect(result.kind).toBe("trigger");
    if (result.kind !== "trigger") throw new Error("expected trigger");
    expect(result.notification.message).toBe("$100.00 → $103.20, crossed 3 × 1.00% steps");
    expect(result.notification.crossedSteps).toBe(3);
  });

  it("ignores disabled rules", () => {
    expect(evaluateAlert({ ...rule, enabled: false }, quote(103), state(100), 10_000)).toEqual({ kind: "none" });
  });

  it("does nothing when quote symbol differs from rule symbol", () => {
    const ethQuote: Quote = { ...quote(101), symbol: "ETH" };
    expect(evaluateAlert(rule, ethQuote, state(100), 10_000)).toEqual({ kind: "none" });
    expect(evaluateAlert(rule, ethQuote, undefined, 10_000)).toEqual({ kind: "none" });
  });

  it("does nothing when current quote price is not positive", () => {
    expect(evaluateAlert(rule, quote(0), state(100), 10_000)).toEqual({ kind: "none" });
    expect(evaluateAlert(rule, quote(-5), state(100), 10_000)).toEqual({ kind: "none" });
    expect(evaluateAlert(rule, quote(0), undefined, 10_000)).toEqual({ kind: "none" });
  });

  it("re-initializes when existing baseline is not positive and current price is valid", () => {
    const result = evaluateAlert(rule, quote(100), state(0), 10_000);
    expect(result).toEqual({
      kind: "initialize",
      nextState: { symbol: "BTC", lastBaselinePrice: 100 },
    });
  });

  it("does not divide by zero when baseline is zero and price is invalid", () => {
    const result = evaluateAlert(rule, quote(0), state(0), 10_000) as { kind: string };
    expect(result.kind).toBe("none");
  });
});

it("does nothing for non-finite current prices", () => {
  expect(evaluateAlert(rule, quote(Number.NaN), state(100), 10_000)).toEqual({ kind: "none" });
  expect(evaluateAlert(rule, quote(Number.POSITIVE_INFINITY), state(100), 10_000)).toEqual({ kind: "none" });
});

it("does not use non-finite baselines", () => {
  expect(evaluateAlert(rule, quote(100), state(Number.NaN), 10_000)).toEqual({
    kind: "initialize",
    nextState: { symbol: "BTC", lastBaselinePrice: 100 },
  });
});
