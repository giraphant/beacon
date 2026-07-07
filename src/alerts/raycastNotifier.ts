import { showToast, Toast } from "@raycast/api";
import type { AlertNotification } from "#/types";

export async function notifyAlert(notification: AlertNotification): Promise<void> {
  await showToast({
    style: Toast.Style.Success,
    title: notification.title,
    message: notification.message,
  });
}
