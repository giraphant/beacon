import type { Quote } from "#/types";
import type { QuoteFetchResult } from "#/quotes/fallback";
import { formatAge, formatPrice } from "#/utils/format";

export type MenuItemModel = { title: string };
export type MenuSectionModel = { title?: string; items: MenuItemModel[] };
export type MenuBarModel = {
  title: string;
  items: MenuItemModel[];
  sections: MenuSectionModel[];
};

export type BuildMenuBarModelInput = {
  displaySymbols: string[];
  quoteResult: QuoteFetchResult | undefined;
  invalidRuleTokens: string[];
  isLoading: boolean;
  now: number;
};

export function buildMenuBarModel(input: BuildMenuBarModelInput): MenuBarModel {
  const quotes = input.quoteResult?.quotes ?? {};
  const displayQuotes = input.displaySymbols.map((symbol) => quotes[symbol]).filter((quote): quote is Quote => Boolean(quote));

  const title = buildTitle(input.displaySymbols, displayQuotes, input.isLoading);
  const items = displayQuotes.map((quote) => ({ title: `${quote.symbol}: ${formatPrice(quote.price)}` }));
  const sections: MenuSectionModel[] = [];

  const sourceLine = buildSourceLine(displayQuotes);

  if (input.quoteResult) {
    const statusItems = [
      sourceLine ? { title: sourceLine } : undefined,
      input.quoteResult.updatedAt ? { title: `Updated: ${formatAge(input.quoteResult.updatedAt, input.now)}` } : undefined,
      input.quoteResult.missingSymbols.length > 0 ? { title: `Not found: ${input.quoteResult.missingSymbols.join(", ")}` } : undefined,
      input.quoteResult.errors.length > 0 ? { title: `Refresh issues: ${input.quoteResult.errors.join("; ")}` } : undefined,
    ].filter((item): item is MenuItemModel => Boolean(item));

    if (statusItems.length > 0) {
      sections.push({ title: "Status", items: statusItems });
    }
  }

  if (input.invalidRuleTokens.length > 0) {
    sections.push({
      title: "Configuration",
      items: [{ title: `Ignored rules: ${input.invalidRuleTokens.join(", ")}` }],
    });
  }

  return { title, items, sections };
}

function buildTitle(displaySymbols: string[], displayQuotes: Quote[], isLoading: boolean) {
  if (displaySymbols.length === 0) {
    return "No symbols";
  }
  if (displayQuotes.length === 0) {
    return isLoading ? "Loading..." : "No prices found";
  }
  return displayQuotes.map((quote) => `${quote.symbol} ${formatPrice(quote.price)}`).join(" · ");
}

function buildSourceLine(displayQuotes: Quote[]): string | undefined {
  if (displayQuotes.length === 0) {
    return undefined;
  }
  const uniqueSources = Array.from(new Set(displayQuotes.map((quote) => quote.source)));
  return `Source: ${uniqueSources.join(", ")}`;
}
