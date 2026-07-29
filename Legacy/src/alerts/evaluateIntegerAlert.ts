import type {
  AlertNotification,
  IntegerAlertBoundaryRange,
  IntegerAlertEvaluation,
  IntegerAlertRule,
  IntegerAlertState,
  Quote,
} from "#/types";
import { formatPrice } from "#/utils/format";

export function evaluateIntegerAlert(
  rule: IntegerAlertRule,
  quote: Quote,
  state: IntegerAlertState | undefined,
  now: number,
  cooldownMs = 0
): IntegerAlertEvaluation {
  if (!rule.enabled || quote.symbol !== rule.symbol || !isPositiveFinite(quote.price) || !isPositiveFinite(rule.step)) {
    return { kind: "none" };
  }

  const currentBucket = Math.floor(quote.price / rule.step + 1e-9);
  if (!state || state.symbol !== rule.symbol || !Number.isFinite(state.lastBucket)) {
    return {
      kind: "initialize",
      nextState: { symbol: rule.symbol, lastBucket: currentBucket, lastPrice: quote.price },
    };
  }

  const bucketDelta = currentBucket - state.lastBucket;
  if (bucketDelta === 0) {
    return { kind: "none" };
  }

  const crossedRange = toRange(state.lastBucket, currentBucket);
  const cooledRanges = getCoolingRanges(state.lastTriggeredBoundaryRanges, now, cooldownMs);
  const freshRange = subtractRanges(crossedRange, cooledRanges)[0];
  if (!freshRange) {
    return {
      kind: "update",
      nextState: { ...state, lastBucket: currentBucket, lastPrice: quote.price },
    };
  }

  const crossedSteps = Math.abs(bucketDelta);
  const direction = bucketDelta > 0 ? "above" : "below";
  const preferredBoundary = bucketDelta > 0 ? currentBucket : state.lastBucket;
  const boundaryBucket = containsBucket(freshRange, preferredBoundary)
    ? preferredBoundary
    : Math.max(...subtractRanges(crossedRange, cooledRanges).map((range) => range.endBucket));
  const boundary = boundaryBucket * rule.step;
  const lastTriggeredBoundaryRanges =
    cooldownMs > 0 ? [...cooledRanges, { ...crossedRange, triggeredAt: now }] : undefined;
  const nextState: IntegerAlertState = {
    symbol: rule.symbol,
    lastBucket: currentBucket,
    lastPrice: quote.price,
    lastTriggeredAt: now,
    lastTriggeredPrice: quote.price,
    ...(lastTriggeredBoundaryRanges ? { lastTriggeredBoundaryRanges } : {}),
  };
  const notification: AlertNotification = {
    symbol: rule.symbol,
    title: `${rule.symbol} crossed ${direction} ${formatPrice(boundary)}`,
    message: `${formatPrice(state.lastPrice)} → ${formatPrice(quote.price)}, crossed ${crossedSteps} × ${formatPrice(
      rule.step
    )} ${crossedSteps === 1 ? "step" : "steps"}`,
    movementPercent: bucketDelta,
    thresholdPercent: rule.step,
    crossedSteps,
    currentPrice: quote.price,
    baselinePrice: state.lastPrice,
  };

  return { kind: "trigger", notification, nextState };
}

function toRange(previousBucket: number, currentBucket: number): IntegerAlertBoundaryRange {
  return {
    startBucket: Math.min(previousBucket, currentBucket) + 1,
    endBucket: Math.max(previousBucket, currentBucket),
    triggeredAt: 0,
  };
}

function getCoolingRanges(ranges: IntegerAlertBoundaryRange[] | undefined, now: number, cooldownMs: number) {
  return cooldownMs > 0 ? (ranges ?? []).filter((range) => now - range.triggeredAt < cooldownMs) : [];
}

function subtractRanges(range: IntegerAlertBoundaryRange, cooledRanges: IntegerAlertBoundaryRange[]) {
  let freshRanges = [range];
  for (const cooledRange of cooledRanges) {
    freshRanges = freshRanges.flatMap((freshRange) => subtractRange(freshRange, cooledRange));
  }
  return freshRanges;
}

function subtractRange(range: IntegerAlertBoundaryRange, cooledRange: IntegerAlertBoundaryRange) {
  if (cooledRange.endBucket < range.startBucket || cooledRange.startBucket > range.endBucket) {
    return [range];
  }
  return [
    range.startBucket < cooledRange.startBucket ? { ...range, endBucket: cooledRange.startBucket - 1 } : undefined,
    range.endBucket > cooledRange.endBucket ? { ...range, startBucket: cooledRange.endBucket + 1 } : undefined,
  ].filter((item): item is IntegerAlertBoundaryRange => Boolean(item));
}

function containsBucket(range: IntegerAlertBoundaryRange, bucket: number) {
  return range.startBucket <= bucket && bucket <= range.endBucket;
}

function isPositiveFinite(value: number) {
  return Number.isFinite(value) && value > 0;
}
