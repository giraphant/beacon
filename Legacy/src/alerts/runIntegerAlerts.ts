import type { AlertNotification, IntegerAlertRule, IntegerAlertState, Quote } from "#/types";
import { evaluateIntegerAlert } from "./evaluateIntegerAlert";

export type RunIntegerAlertsInput = {
  rules: IntegerAlertRule[];
  quotes: Record<string, Quote>;
  now: number;
  integerAlertCooldownMs?: number;
  getState: (symbol: string, step: number) => Promise<IntegerAlertState | undefined>;
  saveState: (state: IntegerAlertState, step: number) => Promise<void>;
  notify: (notification: AlertNotification) => Promise<void>;
};

export type RunIntegerAlertsResult = {
  initialized: number;
  triggered: number;
  skipped: number;
  failed: number;
};

export async function runIntegerAlerts(input: RunIntegerAlertsInput): Promise<RunIntegerAlertsResult> {
  const result: RunIntegerAlertsResult = { initialized: 0, triggered: 0, skipped: 0, failed: 0 };

  for (const rule of input.rules) {
    const quote = input.quotes[rule.symbol];
    if (!quote) {
      result.skipped += 1;
      continue;
    }

    let state: IntegerAlertState | undefined;
    try {
      state = await input.getState(rule.symbol, rule.step);
    } catch {
      result.failed += 1;
      continue;
    }

    const evaluation = evaluateIntegerAlert(rule, quote, state, input.now, input.integerAlertCooldownMs);

    if (evaluation.kind === "none") {
      continue;
    }

    if (evaluation.kind === "update") {
      try {
        await input.saveState(evaluation.nextState, rule.step);
      } catch {
        result.failed += 1;
      }
      continue;
    }

    if (evaluation.kind === "initialize") {
      try {
        await input.saveState(evaluation.nextState, rule.step);
        result.initialized += 1;
      } catch {
        result.failed += 1;
      }
      continue;
    }

    try {
      await input.notify(evaluation.notification);
      await input.saveState(evaluation.nextState, rule.step);
      result.triggered += 1;
    } catch {
      result.failed += 1;
    }
  }

  return result;
}
