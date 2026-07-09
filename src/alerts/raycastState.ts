import { LocalStorage } from "@raycast/api";
import type { AlertState, IntegerAlertState } from "#/types";

const STORAGE_PREFIX = "alert-state:";
const INTEGER_STORAGE_PREFIX = "integer-alert-state:";

export async function getAlertState(symbol: string, thresholdPercent: number): Promise<AlertState | undefined> {
  const value = await LocalStorage.getItem<string>(stateKey(symbol, thresholdPercent));
  if (!value) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(value);
    return isAlertState(parsed, symbol) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

export async function saveAlertState(state: AlertState, thresholdPercent: number): Promise<void> {
  await LocalStorage.setItem(stateKey(state.symbol, thresholdPercent), JSON.stringify(state));
}

export async function getIntegerAlertState(symbol: string, step: number): Promise<IntegerAlertState | undefined> {
  const value = await LocalStorage.getItem<string>(integerStateKey(symbol, step));
  if (!value) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(value);
    return isIntegerAlertState(parsed, symbol) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

export async function saveIntegerAlertState(state: IntegerAlertState, step: number): Promise<void> {
  await LocalStorage.setItem(integerStateKey(state.symbol, step), JSON.stringify(state));
}

function stateKey(symbol: string, thresholdPercent: number) {
  return `${STORAGE_PREFIX}${symbol}:${thresholdPercent}`;
}

function integerStateKey(symbol: string, step: number) {
  return `${INTEGER_STORAGE_PREFIX}${symbol}:${step}`;
}

function isAlertState(value: unknown, symbol: string): value is AlertState {
  if (!value || typeof value !== "object") {
    return false;
  }
  const state = value as Record<string, unknown>;
  return (
    state.symbol === symbol &&
    Number.isFinite(state.lastBaselinePrice) &&
    (state.lastTriggeredAt === undefined || Number.isFinite(state.lastTriggeredAt)) &&
    (state.lastTriggeredPrice === undefined || Number.isFinite(state.lastTriggeredPrice))
  );
}

function isIntegerAlertState(value: unknown, symbol: string): value is IntegerAlertState {
  if (!value || typeof value !== "object") {
    return false;
  }
  const state = value as Record<string, unknown>;
  return (
    state.symbol === symbol &&
    Number.isFinite(state.lastBucket) &&
    Number.isFinite(state.lastPrice) &&
    (state.lastTriggeredAt === undefined || Number.isFinite(state.lastTriggeredAt)) &&
    (state.lastTriggeredPrice === undefined || Number.isFinite(state.lastTriggeredPrice)) &&
    (state.lastTriggeredBoundaryRanges === undefined || isIntegerAlertBoundaryRanges(state.lastTriggeredBoundaryRanges))
  );
}

function isIntegerAlertBoundaryRanges(value: unknown) {
  return (
    Array.isArray(value) &&
    value.every(
      (range) =>
        !!range &&
        typeof range === "object" &&
        Number.isFinite((range as Record<string, unknown>).startBucket) &&
        Number.isFinite((range as Record<string, unknown>).endBucket) &&
        Number.isFinite((range as Record<string, unknown>).triggeredAt)
    )
  );
}
