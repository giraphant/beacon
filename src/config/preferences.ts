import type { AlertRule, ParsedAlertRules } from "#/types";

const SYMBOL_SPLIT_PATTERN = /[\s,|]+/;
const RULE_PATTERN = /^([A-Za-z0-9._-]+):(\d+(?:\.\d+)?)$/;

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
  const rulesBySymbol = new Map<string, AlertRule>();
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
    const thresholdPercent = Number(match[2]);
    if (!symbol || !Number.isFinite(thresholdPercent) || thresholdPercent <= 0) {
      invalidTokens.push(token);
      continue;
    }

    if (rulesBySymbol.has(symbol)) {
      rulesBySymbol.delete(symbol);
    }
    rulesBySymbol.set(symbol, { symbol, thresholdPercent, enabled: true });
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
