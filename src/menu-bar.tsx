import { MenuBarExtra, getPreferenceValues, openCommandPreferences } from "@raycast/api";
import { useCachedState, usePromise } from "@raycast/utils";
import { useEffect, useMemo } from "react";
import { getAlertState, saveAlertState } from "#/alerts/raycastState";
import { notifyAlert } from "#/alerts/raycastNotifier";
import { runAlerts } from "#/alerts/runAlerts";
import { parseAlertRulesText, parseSymbolsText } from "#/config/preferences";
import { buildMenuBarModel } from "#/menu/model";
import { fetchQuotesWithFallback, type QuoteFetchResult } from "#/quotes/fallback";

type MenuBarPreferences = {
  coins?: string;
  alertRules?: string;
};

export default function Command() {
  const preferences = getPreferenceValues<MenuBarPreferences>();
  const displaySymbols = useMemo(() => parseSymbolsText(preferences.coins ?? ""), [preferences.coins]);
  const parsedRules = useMemo(() => parseAlertRulesText(preferences.alertRules ?? ""), [preferences.alertRules]);
  const quoteSymbols = useMemo(
    () => [...new Set([...displaySymbols, ...parsedRules.rules.map((rule) => rule.symbol)])],
    [displaySymbols, parsedRules.rules]
  );

  const [cachedQuotes, setCachedQuotes] = useCachedState<QuoteFetchResult | undefined>("quote-cache", undefined);
  const { data, isLoading, error } = usePromise(fetchQuotesWithFallback, [quoteSymbols], {
    execute: quoteSymbols.length > 0,
    onData: (result) => setCachedQuotes(result),
    onError: () => undefined,
  });

  const quoteResult = data ?? cachedQuotes;

  useEffect(() => {
    if (!quoteResult || parsedRules.rules.length === 0) {
      return;
    }

    runAlerts({
      rules: parsedRules.rules,
      quotes: quoteResult.quotes,
      now: Date.now(),
      getState: getAlertState,
      saveState: saveAlertState,
      notify: notifyAlert,
    });
  }, [quoteResult?.updatedAt, parsedRules.rules]);

  const model = buildMenuBarModel({
    displaySymbols,
    quoteResult: error && cachedQuotes ? { ...cachedQuotes, errors: [error.message] } : quoteResult,
    invalidRuleTokens: parsedRules.invalidTokens,
    isLoading,
    now: Date.now(),
  });

  return (
    <MenuBarExtra isLoading={isLoading} title={model.title}>
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
        <MenuBarExtra.Item title="Settings" onAction={openCommandPreferences} shortcut={{ key: ",", modifiers: ["cmd"] }} />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
