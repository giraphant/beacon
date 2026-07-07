import type { AlertEvaluation, AlertRule, AlertState, Quote } from "#/types";
import { formatPercent, formatPrice } from "#/utils/format";

export function evaluateAlert(
  rule: AlertRule,
  quote: Quote,
  state: AlertState | undefined,
  now: number
): AlertEvaluation {
  if (!rule.enabled) {
    return { kind: "none" };
  }

  if (!state) {
    return {
      kind: "initialize",
      nextState: {
        symbol: rule.symbol,
        lastBaselinePrice: quote.price,
      },
    };
  }

  const movementPercent = ((quote.price - state.lastBaselinePrice) / state.lastBaselinePrice) * 100;
  const absoluteMovementPercent = Math.abs(movementPercent);
  if (absoluteMovementPercent < rule.thresholdPercent) {
    return { kind: "none" };
  }

  const crossedSteps = Math.floor(absoluteMovementPercent / rule.thresholdPercent);
  const verb = movementPercent > 0 ? "rose" : "fell";
  const nextState: AlertState = {
    symbol: rule.symbol,
    lastBaselinePrice: quote.price,
    lastTriggeredAt: now,
    lastTriggeredPrice: quote.price,
  };

  return {
    kind: "trigger",
    notification: {
      symbol: rule.symbol,
      title: `${rule.symbol} ${verb} ${formatPercent(absoluteMovementPercent).replace("+", "")}`,
      message: `${formatPrice(state.lastBaselinePrice)} → ${formatPrice(quote.price)}, crossed ${crossedSteps} × ${formatPercent(
        rule.thresholdPercent
      ).replace("+", "")} steps`,
      movementPercent,
      thresholdPercent: rule.thresholdPercent,
      crossedSteps,
      currentPrice: quote.price,
      baselinePrice: state.lastBaselinePrice,
    },
    nextState,
  };
}
