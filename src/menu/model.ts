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
  titleSymbols?: string[];
  hideTitleSymbols?: boolean;
  hideCurrencySymbol?: boolean;
  quoteResult: QuoteFetchResult | undefined;
  invalidRuleTokens: string[];
  isLoading: boolean;
  now: number;
};

export function buildMenuBarModel(input: BuildMenuBarModelInput): MenuBarModel {
  const quotes = input.quoteResult?.quotes ?? {};
  const displayQuotes = input.displaySymbols.map((symbol) => quotes[symbol]).filter((quote): quote is Quote => Boolean(quote));
  const titleSymbols = input.titleSymbols ?? input.displaySymbols;
  const titleSymbolSet = new Set(titleSymbols);
  const titleQuotes = titleSymbols.map((symbol) => quotes[symbol]).filter((quote): quote is Quote => Boolean(quote));
  const dropdownQuotes = displayQuotes.filter((quote) => !titleSymbolSet.has(quote.symbol));

  const priceFormatOptions = { hideCurrencySymbol: input.hideCurrencySymbol ?? false };
  const title = buildTitle(titleSymbols, titleQuotes, input.isLoading, input.hideTitleSymbols ?? false, priceFormatOptions);
  const items = dropdownQuotes.map((quote) => ({ title: `${quote.symbol}: ${formatPrice(quote.price, priceFormatOptions)}` }));
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

function buildTitle(
  titleSymbols: string[],
  titleQuotes: Quote[],
  isLoading: boolean,
  hideTitleSymbols: boolean,
  priceFormatOptions: { hideCurrencySymbol: boolean }
) {
  if (titleSymbols.length === 0) {
    return "No symbols";
  }
  if (titleQuotes.length === 0) {
    return isLoading ? "Loading..." : "No prices found";
  }
  return titleQuotes
    .map((quote) => (hideTitleSymbols ? formatPrice(quote.price, priceFormatOptions) : `${quote.symbol} ${formatPrice(quote.price, priceFormatOptions)}`))
    .join(" · ");
}

function buildSourceLine(displayQuotes: Quote[]): string | undefined {
  if (displayQuotes.length === 0) {
    return undefined;
  }
  const uniqueSources = Array.from(new Set(displayQuotes.map((quote) => quote.source)));
  return `Source: ${uniqueSources.join(", ")}`;
}
