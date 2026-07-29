import { createRecentAlert, getRecentAlertIndicator } from "#/alerts/recentAlertState";

const notification = {
  symbol: "BTC",
  title: "BTC rose 1.00%",
  message: "$100.00 → $101.00",
  movementPercent: 1,
  thresholdPercent: 1,
  crossedSteps: 1,
  currentPrice: 101,
  baselinePrice: 100,
};

describe("recent alert state", () => {
  test("creates an upward recent alert from a notification", () => {
    expect(createRecentAlert(notification, 10_000)).toEqual({
      symbol: "BTC",
      direction: "up",
      title: "BTC rose 1.00%",
      message: "$100.00 → $101.00",
      triggeredAt: 10_000,
    });
  });

  test("formats alert direction indicators", () => {
    const up = createRecentAlert(notification, 10_000);
    const down = createRecentAlert({ ...notification, movementPercent: -1 }, 10_000);

    expect(getRecentAlertIndicator(up)).toBe("🟢");
    expect(getRecentAlertIndicator(down)).toBe("🔴");
  });
});
