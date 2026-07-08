import { getPreferenceValues, showHUD, showToast, Toast } from "@raycast/api";
import { execFile } from "child_process";
import type { AlertNotification } from "#/types";
import { formatPrice } from "#/utils/format";

type AlertNotifierPreferences = {
  alertSoundEnabled?: boolean;
};

const ALERT_SOUND_PATH = "/System/Library/Sounds/Glass.aiff";

export async function notifyAlert(notification: AlertNotification): Promise<void> {
  const preferences = getPreferenceValues<AlertNotifierPreferences>();
  const indicator = notification.movementPercent > 0 ? "🟢" : "🔴";
  const hudMessage = `${indicator} ${notification.symbol} ${formatPrice(notification.currentPrice)}`;
  let delivered = false;
  let firstError: unknown;

  try {
    await showHUD(hudMessage);
    delivered = true;
  } catch (error) {
    firstError = error;
    console.warn("Failed to show alert HUD:", error);
  }

  if (preferences.alertSoundEnabled) {
    playAlertSound();
  }

  try {
    await showToast({
      style: Toast.Style.Success,
      title: notification.title,
      message: notification.message,
    });
    delivered = true;
  } catch (error) {
    firstError ??= error;
    console.warn("Failed to show alert toast:", error);
  }

  if (!delivered) {
    throw firstError instanceof Error ? firstError : new Error("Failed to deliver alert notification");
  }
}

function playAlertSound() {
  execFile("afplay", [ALERT_SOUND_PATH], (error) => {
    if (error) {
      console.warn("Failed to play alert sound:", error.message);
    }
  });
}
