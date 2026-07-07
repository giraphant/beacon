import type { AlertNotification, AlertRule, AlertState, Quote } from "#/types";
import { evaluateAlert } from "./evaluateAlert";

export type RunAlertsInput = {
  rules: AlertRule[];
  quotes: Record<string, Quote>;
  now: number;
  getState: (symbol: string) => Promise<AlertState | undefined>;
  saveState: (state: AlertState) => Promise<void>;
  notify: (notification: AlertNotification) => Promise<void>;
};

export type RunAlertsResult = {
  initialized: number;
  triggered: number;
  skipped: number;
  failed: number;
};

export async function runAlerts(input: RunAlertsInput): Promise<RunAlertsResult> {
  const result: RunAlertsResult = { initialized: 0, triggered: 0, skipped: 0, failed: 0 };

  for (const rule of input.rules) {
    const quote = input.quotes[rule.symbol];
    if (!quote) {
      result.skipped += 1;
      continue;
    }

    const state = await input.getState(rule.symbol);
    const evaluation = evaluateAlert(rule, quote, state, input.now);

    if (evaluation.kind === "none") {
      continue;
    }

    if (evaluation.kind === "initialize") {
      await input.saveState(evaluation.nextState);
      result.initialized += 1;
      continue;
    }

    try {
      await input.notify(evaluation.notification);
      await input.saveState(evaluation.nextState);
      result.triggered += 1;
    } catch {
      result.failed += 1;
    }
  }

  return result;
}
