import type { AlertNotification } from "#/types";

export const RECENT_ALERTS_CACHE_KEY = "recent-alerts";

export type RecentAlert = {
  symbol: string;
  direction: "up" | "down";
  title: string;
  message: string;
  triggeredAt: number;
};

export type RecentAlertsBySymbol = Record<string, RecentAlert>;

export function createRecentAlert(notification: AlertNotification, triggeredAt: number = Date.now()): RecentAlert {
  return {
    symbol: notification.symbol,
    direction: notification.movementPercent > 0 ? "up" : "down",
    title: notification.title,
    message: notification.message,
    triggeredAt,
  };
}

export function getRecentAlertIndicator(alert: RecentAlert): string {
  return alert.direction === "up" ? "🟢" : "🔴";
}
