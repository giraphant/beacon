import { Color, Icon, MenuBarExtra, getPreferenceValues, openCommandPreferences, showHUD } from "@raycast/api";
import { useCachedState, usePromise } from "@raycast/utils";
import { useEffect, useMemo } from "react";
import {
  createAlertRuleSignature,
  createFreshQuoteAlertScheduler,
  createIntegerAlertRuleSignature,
  createQuoteSymbolSignature,
} from "#/alerts/freshQuoteAlertScheduler";
import { createRecentAlert, RECENT_ALERTS_CACHE_KEY, type RecentAlertsBySymbol } from "#/alerts/recentAlertState";
import { getAlertState, getIntegerAlertState, saveAlertState, saveIntegerAlertState } from "#/alerts/raycastState";
import { notifyAlert } from "#/alerts/raycastNotifier";
import { runAlerts } from "#/alerts/runAlerts";
import { runIntegerAlerts } from "#/alerts/runIntegerAlerts";
import {
  parseAlertRulesText,
  parseCoinDisplayText,
  parseIntegerAlertCooldownMinutes,
  parseIntegerAlertRulesText,
} from "#/config/preferences";
import { buildMenuBarModel, resolveActiveQuoteResult } from "#/menu/model";
import { createQuoteSourceSignature, fetchQuotesForSource, type QuoteSource } from "#/quotes/source";
import type { QuoteFetchResult } from "#/quotes/types";
import { createTaggedQuoteCacheEntry, readTaggedQuoteCache, type TaggedQuoteCacheEntry } from "#/quotes/quoteCache";

type MenuBarPreferences = {
  coins?: string;
  alertRules?: string;
  integerAlertRules?: string;
  integerAlertCooldownMinutes?: string;
  hideMenuBarSymbols?: boolean;
  hideCurrencySymbol?: boolean;
  source?: QuoteSource;
  relayUrl?: string;
  relayToken?: string;
};

type TaggedQuoteFetchResult = {
  result: QuoteFetchResult;
  ruleSignature: string;
  quoteSymbolSignature: string;
  sourceSignature: string;
};

async function fetchTaggedQuotes(
  symbols: string[],
  ruleSignature: string,
  quoteSymbolSignature: string,
  source: QuoteSource,
  relayUrl: string | undefined,
  relayToken: string | undefined
): Promise<TaggedQuoteFetchResult> {
  const result = await fetchQuotesForSource(symbols, source, relayUrl, relayToken);
  return {
    result,
    ruleSignature,
    quoteSymbolSignature,
    sourceSignature: createQuoteSourceSignature(source, relayUrl),
  };
}

export default function Command() {
  const preferences = getPreferenceValues<MenuBarPreferences>();
  const coinDisplay = useMemo(() => parseCoinDisplayText(preferences.coins ?? ""), [preferences.coins]);
  const displaySymbols = coinDisplay.quoteSymbols;
  const titleSymbols = coinDisplay.titleSymbols;
  const parsedRules = useMemo(() => parseAlertRulesText(preferences.alertRules ?? ""), [preferences.alertRules]);
  const parsedIntegerRules = useMemo(
    () => parseIntegerAlertRulesText(preferences.integerAlertRules ?? ""),
    [preferences.integerAlertRules]
  );
  const integerAlertCooldownMs = parseIntegerAlertCooldownMinutes(preferences.integerAlertCooldownMinutes) * 60_000;
  const quoteSymbols = useMemo(
    () => [
      ...new Set([
        ...displaySymbols,
        ...parsedRules.rules.map((rule) => rule.symbol),
        ...parsedIntegerRules.rules.map((rule) => rule.symbol),
      ]),
    ],
    [displaySymbols, parsedRules.rules, parsedIntegerRules.rules]
  );
  const ruleSignature = useMemo(
    () =>
      [createAlertRuleSignature(parsedRules.rules), createIntegerAlertRuleSignature(parsedIntegerRules.rules)].join(
        "||"
      ),
    [parsedRules.rules, parsedIntegerRules.rules]
  );
  const source = preferences.source ?? "Bybit";
  const relayUrl = preferences.relayUrl?.trim() ?? "";
  const quoteSourceSignature = createQuoteSourceSignature(source, relayUrl);
  const quoteSymbolSignature = useMemo(
    () => `${quoteSourceSignature}:${createQuoteSymbolSignature(quoteSymbols)}`,
    [quoteSourceSignature, quoteSymbols]
  );
  const [recentAlerts, setRecentAlerts] = useCachedState<RecentAlertsBySymbol>(RECENT_ALERTS_CACHE_KEY, {});
  const alertScheduler = useMemo(
    () =>
      createFreshQuoteAlertScheduler({
        runAlerts: async ({ rules, integerRules, quotes, now, integerAlertCooldownMs }) => {
          const notify = async (notification: Parameters<typeof notifyAlert>[0]) => {
            await notifyAlert(notification);
            setRecentAlerts((alerts) => ({ ...alerts, [notification.symbol]: createRecentAlert(notification, now) }));
          };

          await runAlerts({
            rules,
            quotes,
            now,
            getState: getAlertState,
            saveState: saveAlertState,
            notify,
          });
          await runIntegerAlerts({
            rules: integerRules,
            quotes,
            now,
            integerAlertCooldownMs,
            getState: getIntegerAlertState,
            saveState: saveIntegerAlertState,
            notify,
          });
        },
      }),
    [setRecentAlerts]
  );

  const [cachedQuotes, setCachedQuotes] = useCachedState<TaggedQuoteCacheEntry | undefined>("quote-cache", undefined);
  const { data, isLoading, error } = usePromise(
    fetchTaggedQuotes,
    [quoteSymbols, ruleSignature, quoteSymbolSignature, source, relayUrl, preferences.relayToken],
    {
      execute: quoteSymbols.length > 0,
      onData: ({ result, sourceSignature: capturedSourceSignature }) =>
        setCachedQuotes(createTaggedQuoteCacheEntry(result, capturedSourceSignature)),
      onError: () => undefined,
    }
  );

  const cachedResult = readTaggedQuoteCache(cachedQuotes, quoteSourceSignature);
  const quoteResult = resolveActiveQuoteResult({
    data: data ? { result: data.result, sourceSignature: data.sourceSignature } : undefined,
    activeSourceSignature: quoteSourceSignature,
    error: error ?? undefined,
    cachedResult,
  });

  useEffect(() => {
    if (!data) {
      return;
    }

    alertScheduler.submitFreshQuoteResult({
      rules: parsedRules.rules,
      integerRules: parsedIntegerRules.rules,
      quotes: data.result.quotes,
      fetchRuleSignature: data.ruleSignature,
      currentRuleSignature: ruleSignature,
      fetchQuoteSymbolSignature: data.quoteSymbolSignature,
      currentQuoteSymbolSignature: quoteSymbolSignature,
      now: Date.now(),
      integerAlertCooldownMs,
    });
  }, [
    data,
    alertScheduler,
    parsedRules.rules,
    parsedIntegerRules.rules,
    ruleSignature,
    quoteSymbolSignature,
    integerAlertCooldownMs,
  ]);

  const model = buildMenuBarModel({
    displaySymbols,
    titleSymbols,
    hideTitleSymbols: preferences.hideMenuBarSymbols ?? false,
    hideCurrencySymbol: preferences.hideCurrencySymbol ?? false,
    quoteResult,
    invalidRuleTokens: parsedRules.invalidTokens,
    invalidIntegerRuleTokens: parsedIntegerRules.invalidTokens,
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
    <MenuBarExtra icon={alertIcon} isLoading={model.isLoading} title={model.title}>
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
