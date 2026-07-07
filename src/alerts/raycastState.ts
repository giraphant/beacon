import { LocalStorage } from "@raycast/api";
import type { AlertState } from "#/types";

const STORAGE_PREFIX = "alert-state:";

export async function getAlertState(symbol: string): Promise<AlertState | undefined> {
  const value = await LocalStorage.getItem<string>(`${STORAGE_PREFIX}${symbol}`);
  if (!value) {
    return undefined;
  }

  try {
    return JSON.parse(value) as AlertState;
  } catch {
    return undefined;
  }
}

export async function saveAlertState(state: AlertState): Promise<void> {
  await LocalStorage.setItem(`${STORAGE_PREFIX}${state.symbol}`, JSON.stringify(state));
}
