import type { AlertRule, IntegerAlertRule, Quote } from "#/types";

export type FreshQuoteAlertRunInput = {
  rules: AlertRule[];
  integerRules: IntegerAlertRule[];
  quotes: Record<string, Quote>;
  now: number;
  integerAlertCooldownMs?: number;
};

export type FreshQuoteAlertSchedulerInput = FreshQuoteAlertRunInput & {
  fetchRuleSignature: string;
  currentRuleSignature: string;
  fetchQuoteSymbolSignature: string;
  currentQuoteSymbolSignature: string;
};

type SchedulerOptions = {
  runAlerts: (input: FreshQuoteAlertRunInput) => Promise<unknown>;
};

export type FreshQuoteAlertScheduler = {
  submitFreshQuoteResult: (input: FreshQuoteAlertSchedulerInput) => void;
  waitForIdle: () => Promise<void>;
};

export function createFreshQuoteAlertScheduler(options: SchedulerOptions): FreshQuoteAlertScheduler {
  let inFlight: Promise<void> | undefined;
  let queuedInput: FreshQuoteAlertRunInput | undefined;

  function submitFreshQuoteResult(input: FreshQuoteAlertSchedulerInput) {
    if (
      input.fetchRuleSignature !== input.currentRuleSignature ||
      input.fetchQuoteSymbolSignature !== input.currentQuoteSymbolSignature ||
      (input.rules.length === 0 && input.integerRules.length === 0)
    ) {
      return;
    }

    queuedInput = {
      rules: input.rules,
      integerRules: input.integerRules,
      quotes: input.quotes,
      now: input.now,
      integerAlertCooldownMs: input.integerAlertCooldownMs,
    };

    if (!inFlight) {
      inFlight = drainQueue();
    }
  }

  async function drainQueue() {
    try {
      while (queuedInput) {
        const nextInput = queuedInput;
        queuedInput = undefined;
        await options.runAlerts(nextInput);
      }
    } catch {
      // Alert delivery must not break menu-bar rendering or future alert runs.
    } finally {
      inFlight = undefined;
      if (queuedInput) {
        inFlight = drainQueue();
      }
    }
  }

  async function waitForIdle() {
    while (inFlight) {
      await inFlight;
    }
  }

  return { submitFreshQuoteResult, waitForIdle };
}

export function createAlertRuleSignature(rules: AlertRule[]): string {
  return rules.map((rule) => `${rule.symbol}:${rule.thresholdPercent}:${rule.enabled ? "1" : "0"}`).join("|");
}

export function createIntegerAlertRuleSignature(rules: IntegerAlertRule[]): string {
  return rules.map((rule) => `${rule.symbol}:${rule.step}:${rule.enabled ? "1" : "0"}`).join("|");
}

export function createQuoteSymbolSignature(symbols: string[]): string {
  return symbols.join("|");
}
