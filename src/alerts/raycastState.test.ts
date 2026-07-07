import { LocalStorage } from "@raycast/api";
import { getAlertState, saveAlertState } from "#/alerts/raycastState";

jest.mock(
  "@raycast/api",
  () => ({
    LocalStorage: {
      getItem: jest.fn(),
      setItem: jest.fn(),
    },
  }),
  { virtual: true }
);

const mockedLocalStorage = LocalStorage as jest.Mocked<typeof LocalStorage>;

describe("Raycast alert state adapter", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("returns parsed alert state from namespaced LocalStorage key", async () => {
    mockedLocalStorage.getItem.mockResolvedValueOnce(
      JSON.stringify({ symbol: "BTC", lastBaselinePrice: 100, lastTriggeredAt: 123, lastTriggeredPrice: 105 })
    );

    await expect(getAlertState("BTC")).resolves.toEqual({
      symbol: "BTC",
      lastBaselinePrice: 100,
      lastTriggeredAt: 123,
      lastTriggeredPrice: 105,
    });
    expect(mockedLocalStorage.getItem).toHaveBeenCalledWith("alert-state:BTC");
  });

  test("returns undefined when stored alert state is missing or invalid", async () => {
    mockedLocalStorage.getItem.mockResolvedValueOnce(undefined).mockResolvedValueOnce("not json");

    await expect(getAlertState("ETH")).resolves.toBeUndefined();
    await expect(getAlertState("SOL")).resolves.toBeUndefined();
  });

  test("saves serialized alert state under namespaced LocalStorage key", async () => {
    await saveAlertState({ symbol: "ETH", lastBaselinePrice: 200 });

    expect(mockedLocalStorage.setItem).toHaveBeenCalledWith(
      "alert-state:ETH",
      JSON.stringify({ symbol: "ETH", lastBaselinePrice: 200 })
    );
  });
});
