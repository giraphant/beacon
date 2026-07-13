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
import { buildMenuBarModel } from "#/menu/model";
import { fetchRelayQuotes, type QuoteFetchResult } from "#/quotes/relay";

type MenuBarPreferences = {
  coins?: string;
  alertRules?: string;
  integerAlertRules?: string;
  integerAlertCooldownMinutes?: string;
  hideMenuBarSymbols?: boolean;
  hideCurrencySymbol?: boolean;
  relayUrl?: string;
  relayToken?: string;
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
  relayUrl: string | undefined,
  relayToken: string | undefined
): Promise<TaggedQuoteFetchResult> {
  return {
    result: await fetchRelayQuotes(symbols, relayUrl, relayToken),
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
  const relayUrl = preferences.relayUrl?.trim() ?? "";
  const quoteSymbolSignature = useMemo(
    () => `${relayUrl}:${createQuoteSymbolSignature(quoteSymbols)}`,
    [relayUrl, quoteSymbols]
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

  const [cachedQuotes, setCachedQuotes] = useCachedState<QuoteFetchResult | undefined>("quote-cache", undefined);
  const { data, isLoading, error } = usePromise(
    fetchTaggedQuotes,
    [quoteSymbols, ruleSignature, quoteSymbolSignature, relayUrl, preferences.relayToken],
    {
      execute: quoteSymbols.length > 0,
      onData: ({ result }) => setCachedQuotes(result),
      onError: () => undefined,
    }
  );

  const quoteResult =
    data?.result ??
    (error
      ? cachedQuotes
        ? { ...cachedQuotes, errors: [error.message] }
        : { quotes: {}, missingSymbols: [], errors: [error.message], updatedAt: 0 }
      : cachedQuotes);

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
