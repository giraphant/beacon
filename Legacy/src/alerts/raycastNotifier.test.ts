import { getPreferenceValues, showHUD, showToast, Toast } from "@raycast/api";
import { execFile } from "child_process";
import { notifyAlert } from "#/alerts/raycastNotifier";
import type { AlertNotification } from "#/types";

jest.mock(
  "@raycast/api",
  () => ({
    getPreferenceValues: jest.fn(),
    showHUD: jest.fn(),
    showToast: jest.fn(),
    Toast: {
      Style: {
        Success: "success",
      },
    },
  }),
  { virtual: true }
);

jest.mock("child_process", () => ({
  execFile: jest.fn(),
}));

const mockedGetPreferenceValues = getPreferenceValues as jest.MockedFunction<typeof getPreferenceValues>;
const mockedShowHUD = showHUD as jest.MockedFunction<typeof showHUD>;
const mockedShowToast = showToast as jest.MockedFunction<typeof showToast>;
const mockedExecFile = execFile as unknown as jest.Mock;
type ShowToastResult = Awaited<ReturnType<typeof showToast>>;

const notification: AlertNotification = {
  symbol: "BTC",
  title: "BTC moved 2.00%",
  message: "$102.00 from $100.00",
  movementPercent: 2,
  thresholdPercent: 2,
  crossedSteps: 1,
  currentPrice: 102,
  baselinePrice: 100,
};

describe("Raycast alert notifier", () => {
  let warnSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.clearAllMocks();
    mockedGetPreferenceValues.mockReturnValue({ alertSoundEnabled: false });
    mockedShowHUD.mockResolvedValue(undefined);
    mockedShowToast.mockResolvedValue({} as ShowToastResult);
    mockedExecFile.mockImplementation((_command: string, _args: string[], callback?: (error: Error | null) => void) => {
      callback?.(null);
    });
    warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
  });

  afterEach(() => {
    warnSpy.mockRestore();
  });

  test("shows a HUD and successful Raycast toast with alert title and message", async () => {
    await notifyAlert(notification);

    expect(mockedShowHUD).toHaveBeenCalledWith("🟢 BTC $102.00");
    expect(mockedShowToast).toHaveBeenCalledWith({
      style: Toast.Style.Success,
      title: "BTC moved 2.00%",
      message: "$102.00 from $100.00",
    });
  });

  test("does not play sound when alert sound preference is off", async () => {
    await notifyAlert(notification);

    expect(mockedExecFile).not.toHaveBeenCalled();
  });

  test("plays a best-effort sound when alert sound preference is on", async () => {
    mockedGetPreferenceValues.mockReturnValue({ alertSoundEnabled: true });

    await notifyAlert(notification);

    expect(mockedExecFile).toHaveBeenCalledWith("afplay", ["/System/Library/Sounds/Glass.aiff"], expect.any(Function));
  });

  test("does not reject when sound playback fails after HUD and toast delivery", async () => {
    mockedGetPreferenceValues.mockReturnValue({ alertSoundEnabled: true });
    mockedExecFile.mockImplementation((_command: string, _args: string[], callback?: (error: Error | null) => void) => {
      callback?.(new Error("sound failed"));
    });

    await expect(notifyAlert(notification)).resolves.toBeUndefined();
    expect(warnSpy).toHaveBeenCalledWith("Failed to play alert sound:", "sound failed");
  });

  test("uses toast as a fallback when HUD delivery fails", async () => {
    mockedShowHUD.mockRejectedValueOnce(new Error("hud failed"));

    await expect(notifyAlert(notification)).resolves.toBeUndefined();
    expect(mockedShowToast).toHaveBeenCalled();
  });
});
