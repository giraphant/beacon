import { Color, Icon, MenuBarExtra, getPreferenceValues, openCommandPreferences, showHUD } from "@raycast/api";
import { useCachedState, usePromise } from "@raycast/utils";
import { useEffect, useMemo } from "react";
import {
  createAlertRuleSignature,
  createFreshQuoteAlertScheduler,
  createQuoteSymbolSignature,
} from "#/alerts/freshQuoteAlertScheduler";
import { createRecentAlert, RECENT_ALERTS_CACHE_KEY, type RecentAlertsBySymbol } from "#/alerts/recentAlertState";
import { getAlertState, saveAlertState } from "#/alerts/raycastState";
import { notifyAlert } from "#/alerts/raycastNotifier";
import { runAlerts } from "#/alerts/runAlerts";
import { parseAlertRulesText, parseCoinDisplayText } from "#/config/preferences";
import { buildMenuBarModel } from "#/menu/model";
import { fetchQuotesWithFallback, type PreferredQuoteSource, type QuoteFetchResult } from "#/quotes/fallback";

type MenuBarPreferences = {
  coins?: string;
  alertRules?: string;
  hideMenuBarSymbols?: boolean;
  hideCurrencySymbol?: boolean;
  source?: PreferredQuoteSource;
};

type TaggedQuoteFetchResult = {
  result: QuoteFetchResult;
  ruleSignature: string;
  quoteSymbolSignature: string;
};

async function fetchTaggedQuotes(
  symbols: string[],
  ruleSignature: string,
  quoteSymbolSignature: string,
  preferredSource: PreferredQuoteSource | undefined
): Promise<TaggedQuoteFetchResult> {
  return {
    result: await fetchQuotesWithFallback(symbols, preferredSource),
    ruleSignature,
    quoteSymbolSignature,
  };
}

export default function Command() {
  const preferences = getPreferenceValues<MenuBarPreferences>();
  const coinDisplay = useMemo(() => parseCoinDisplayText(preferences.coins ?? ""), [preferences.coins]);
  const displaySymbols = coinDisplay.quoteSymbols;
  const titleSymbols = coinDisplay.titleSymbols;
  const parsedRules = useMemo(() => parseAlertRulesText(preferences.alertRules ?? ""), [preferences.alertRules]);
  const quoteSymbols = useMemo(
    () => [...new Set([...displaySymbols, ...parsedRules.rules.map((rule) => rule.symbol)])],
    [displaySymbols, parsedRules.rules]
  );
  const ruleSignature = useMemo(() => createAlertRuleSignature(parsedRules.rules), [parsedRules.rules]);
  const preferredSource = preferences.source ?? "Bybit";
  const quoteSymbolSignature = useMemo(
    () => `${preferredSource}:${createQuoteSymbolSignature(quoteSymbols)}`,
    [preferredSource, quoteSymbols]
  );
  const [recentAlerts, setRecentAlerts] = useCachedState<RecentAlertsBySymbol>(RECENT_ALERTS_CACHE_KEY, {});
  const alertScheduler = useMemo(
    () =>
      createFreshQuoteAlertScheduler({
        runAlerts: ({ rules, quotes, now }) =>
          runAlerts({
            rules,
            quotes,
            now,
            getState: getAlertState,
            saveState: saveAlertState,
            notify: async (notification) => {
              await notifyAlert(notification);
              setRecentAlerts((alerts) => ({ ...alerts, [notification.symbol]: createRecentAlert(notification, now) }));
            },
          }),
      }),
    [setRecentAlerts]
  );

  const [cachedQuotes, setCachedQuotes] = useCachedState<QuoteFetchResult | undefined>("quote-cache", undefined);
  const { data, isLoading, error } = usePromise(
    fetchTaggedQuotes,
    [quoteSymbols, ruleSignature, quoteSymbolSignature, preferredSource],
    {
      execute: quoteSymbols.length > 0,
      onData: ({ result }) => setCachedQuotes(result),
      onError: () => undefined,
    }
  );

  const quoteResult = data?.result ?? cachedQuotes;

  useEffect(() => {
    if (!data) {
      return;
    }

    alertScheduler.submitFreshQuoteResult({
      rules: parsedRules.rules,
      quotes: data.result.quotes,
      fetchRuleSignature: data.ruleSignature,
      currentRuleSignature: ruleSignature,
      fetchQuoteSymbolSignature: data.quoteSymbolSignature,
      currentQuoteSymbolSignature: quoteSymbolSignature,
      now: Date.now(),
    });
  }, [data, alertScheduler, parsedRules.rules, ruleSignature, quoteSymbolSignature]);

  const model = buildMenuBarModel({
    displaySymbols,
    titleSymbols,
    hideTitleSymbols: preferences.hideMenuBarSymbols ?? false,
    hideCurrencySymbol: preferences.hideCurrencySymbol ?? false,
    quoteResult: error && cachedQuotes ? { ...cachedQuotes, errors: [error.message] } : quoteResult,
    invalidRuleTokens: parsedRules.invalidTokens,
    recentAlerts,
    isLoading,
    now: Date.now(),
  });
  const recentAlertValues = Object.values(recentAlerts);
  const alertIcon =
    recentAlertValues.length > 0
      ? {
          source: Icon.CircleFilled,
          tintColor: recentAlertValues.some((alert) => alert.direction === "down") ? Color.Red : Color.Green,
        }
      : undefined;

  return (
    <MenuBarExtra icon={alertIcon} isLoading={isLoading} title={model.title}>
      {model.items.map((item) => (
        <MenuBarExtra.Item key={item.title} title={item.title} onAction={() => undefined} />
      ))}
      {model.sections.map((section) => (
        <MenuBarExtra.Section key={section.title ?? "section"} title={section.title}>
          {section.items.map((item) => (
            <MenuBarExtra.Item key={item.title} title={item.title} onAction={() => undefined} />
          ))}
        </MenuBarExtra.Section>
      ))}
      <MenuBarExtra.Section>
        {Object.keys(recentAlerts).length > 0 && (
          <MenuBarExtra.Item
            title="Dismiss Alerts"
            onAction={() => {
              setRecentAlerts({});
              showHUD("Beacon alerts dismissed");
            }}
          />
        )}
        <MenuBarExtra.Item
          title="Settings"
          onAction={openCommandPreferences}
          shortcut={{ key: ",", modifiers: ["cmd"] }}
        />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
