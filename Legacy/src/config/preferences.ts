import type { AlertRule, IntegerAlertRule, ParsedAlertRules, ParsedIntegerAlertRules } from "#/types";

const SYMBOL_SPLIT_PATTERN = /[\s,|]+/;
const RULE_PATTERN = /^([A-Za-z0-9._-]+):(\d+(?:\.\d+)?)$/;
const DEFAULT_INTEGER_ALERT_COOLDOWN_MINUTES = 10;

export function parseSymbolsText(text: string): string[] {
  return parseSymbolTokens(text);
}

export function parseCoinDisplayText(text: string): { titleSymbols: string[]; quoteSymbols: string[] } {
  const pipeIndex = text.indexOf("|");
  if (pipeIndex === -1) {
    const symbols = parseSymbolTokens(text);
    return { titleSymbols: symbols, quoteSymbols: symbols };
  }

  const titleSymbols = parseSymbolTokens(text.slice(0, pipeIndex));
  const dropdownOnlySymbols = parseSymbolTokens(text.slice(pipeIndex + 1));
  return { titleSymbols, quoteSymbols: dedupeSymbols([...titleSymbols, ...dropdownOnlySymbols]) };
}

export function parseAlertRulesText(text: string): ParsedAlertRules {
  return parseRuleTokens<AlertRule>(text, (symbol, value) => ({ symbol, thresholdPercent: value, enabled: true }));
}

export function parseIntegerAlertRulesText(text: string): ParsedIntegerAlertRules {
  return parseRuleTokens<IntegerAlertRule>(text, (symbol, value) => ({ symbol, step: value, enabled: true }));
}

export function parseIntegerAlertCooldownMinutes(text: string | undefined): number {
  const value = text?.trim() === "" ? Number.NaN : Number(text);
  return Number.isFinite(value) && value >= 0 ? value : DEFAULT_INTEGER_ALERT_COOLDOWN_MINUTES;
}

function parseRuleTokens<T>(text: string, createRule: (symbol: string, value: number) => T) {
  const rulesBySymbol = new Map<string, T>();
  const invalidTokens: string[] = [];

  for (const rawToken of text.split(SYMBOL_SPLIT_PATTERN)) {
    const token = rawToken.trim();
    if (!token) {
      continue;
    }

    const match = token.match(RULE_PATTERN);
    if (!match) {
      invalidTokens.push(token);
      continue;
    }

    const symbol = normalizeSymbol(match[1]);
    const value = Number(match[2]);
    if (!symbol || !Number.isFinite(value) || value <= 0) {
      invalidTokens.push(token);
      continue;
    }

    if (rulesBySymbol.has(symbol)) {
      rulesBySymbol.delete(symbol);
    }
    rulesBySymbol.set(symbol, createRule(symbol, value));
  }

  return { rules: [...rulesBySymbol.values()], invalidTokens };
}

function parseSymbolTokens(text: string): string[] {
  return dedupeSymbols(text.split(SYMBOL_SPLIT_PATTERN).map(normalizeSymbol));
}

function dedupeSymbols(values: string[]): string[] {
  const seen = new Set<string>();
  const symbols: string[] = [];

  for (const symbol of values) {
    if (!symbol || seen.has(symbol)) {
      continue;
    }
    seen.add(symbol);
    symbols.push(symbol);
  }

  return symbols;
}

function normalizeSymbol(value: string) {
  return value.trim().toUpperCase();
}
