import { LocalStorage } from "@raycast/api";
import type { AlertState } from "#/types";

const STORAGE_PREFIX = "alert-state:";

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

function stateKey(symbol: string, thresholdPercent: number) {
  return `${STORAGE_PREFIX}${symbol}:${thresholdPercent}`;
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
