import type { Quote } from "#/types";
import type { QuoteFetchResult } from "#/quotes/fallback";
import type { RecentAlertsBySymbol } from "#/alerts/recentAlertState";
import { getRecentAlertIndicator } from "#/alerts/recentAlertState";
import { formatAge, formatPrice } from "#/utils/format";

export type MenuItemModel = { title: string };
export type MenuSectionModel = { title?: string; items: MenuItemModel[] };
export type MenuBarModel = {
  title: string;
  isLoading: boolean;
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
  invalidIntegerRuleTokens?: string[];
  recentAlerts?: RecentAlertsBySymbol;
  isLoading: boolean;
  now: number;
};

export function buildMenuBarModel(input: BuildMenuBarModelInput): MenuBarModel {
  const quotes = input.quoteResult?.quotes ?? {};
  const displayQuotes = input.displaySymbols
    .map((symbol) => quotes[symbol])
    .filter((quote): quote is Quote => Boolean(quote));
  const titleSymbols = input.titleSymbols ?? input.displaySymbols;
  const titleSymbolSet = new Set(titleSymbols);
  const titleQuotes = titleSymbols.map((symbol) => quotes[symbol]).filter((quote): quote is Quote => Boolean(quote));
  const dropdownQuotes = displayQuotes.filter((quote) => !titleSymbolSet.has(quote.symbol));

  const recentAlerts = input.recentAlerts ?? {};
  const priceFormatOptions = { hideCurrencySymbol: input.hideCurrencySymbol ?? false };
  const title = buildTitle(
    titleSymbols,
    titleQuotes,
    input.isLoading,
    input.hideTitleSymbols ?? false,
    priceFormatOptions
  );
  const isLoading = input.isLoading && titleQuotes.length === 0;
  const items = dropdownQuotes.map((quote) => ({
    title: formatQuoteTitle(quote, false, priceFormatOptions, recentAlerts, true),
  }));
  const sections: MenuSectionModel[] = [];

  const sourceLine = buildSourceLine(displayQuotes);

  if (input.quoteResult) {
    const statusItems = [
      sourceLine ? { title: sourceLine } : undefined,
      input.quoteResult.updatedAt
        ? { title: `Updated: ${formatAge(input.quoteResult.updatedAt, input.now)}` }
        : undefined,
      input.quoteResult.missingSymbols.length > 0
        ? { title: `Not found: ${input.quoteResult.missingSymbols.join(", ")}` }
        : undefined,
      input.quoteResult.errors.length > 0
        ? { title: `Refresh issues: ${input.quoteResult.errors.join("; ")}` }
        : undefined,
    ].filter((item): item is MenuItemModel => Boolean(item));

    if (statusItems.length > 0) {
      sections.push({ title: "Status", items: statusItems });
    }
  }

  const configurationItems = [
    input.invalidRuleTokens.length > 0 ? { title: `Ignored rules: ${input.invalidRuleTokens.join(", ")}` } : undefined,
    input.invalidIntegerRuleTokens && input.invalidIntegerRuleTokens.length > 0
      ? { title: `Ignored integer rules: ${input.invalidIntegerRuleTokens.join(", ")}` }
      : undefined,
  ].filter((item): item is MenuItemModel => Boolean(item));

  if (configurationItems.length > 0) {
    sections.push({ title: "Configuration", items: configurationItems });
  }

  return { title, isLoading, items, sections };
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
  return titleQuotes.map((quote) => formatTitleQuote(quote, hideTitleSymbols, priceFormatOptions)).join(" · ");
}

function formatTitleQuote(quote: Quote, hideSymbol: boolean, priceFormatOptions: { hideCurrencySymbol: boolean }) {
  const price = formatPrice(quote.price, priceFormatOptions);
  return hideSymbol ? price : `${quote.symbol} ${price}`;
}

function formatQuoteTitle(
  quote: Quote,
  hideSymbol: boolean,
  priceFormatOptions: { hideCurrencySymbol: boolean },
  recentAlerts: RecentAlertsBySymbol,
  useDropdownSeparator = false
) {
  const alert = recentAlerts[quote.symbol];
  const alertPrefix = alert ? `${getRecentAlertIndicator(alert)} ` : "";
  const price = formatPrice(quote.price, priceFormatOptions);
  const separator = useDropdownSeparator ? ": " : " ";
  return hideSymbol ? `${alertPrefix}${price}` : `${alertPrefix}${quote.symbol}${separator}${price}`;
}

function buildSourceLine(displayQuotes: Quote[]): string | undefined {
  if (displayQuotes.length === 0) {
    return undefined;
  }
  const uniqueSources = Array.from(new Set(displayQuotes.map((quote) => quote.source)));
  return `Source: ${uniqueSources.join(", ")}`;
}
