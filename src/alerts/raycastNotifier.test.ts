import { showToast, Toast } from "@raycast/api";
import { notifyAlert } from "#/alerts/raycastNotifier";

jest.mock(
  "@raycast/api",
  () => ({
    showToast: jest.fn(),
    Toast: {
      Style: {
        Success: "success",
      },
    },
  }),
  { virtual: true }
);

const mockedShowToast = showToast as jest.MockedFunction<typeof showToast>;

describe("Raycast alert notifier", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("shows successful Raycast toast with alert title and message", async () => {
    await notifyAlert({
      symbol: "BTC",
      title: "BTC moved 2.00%",
      message: "$102.00 from $100.00",
      movementPercent: 2,
      thresholdPercent: 2,
      crossedSteps: 1,
      currentPrice: 102,
      baselinePrice: 100,
    });

    expect(mockedShowToast).toHaveBeenCalledWith({
      style: Toast.Style.Success,
      title: "BTC moved 2.00%",
      message: "$102.00 from $100.00",
    });
  });
});
