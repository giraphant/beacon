import { LocalStorage } from "@raycast/api";
import { getAlertState, saveAlertState, getIntegerAlertState, saveIntegerAlertState } from "#/alerts/raycastState";

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

    await expect(getAlertState("BTC", 1)).resolves.toEqual({
      symbol: "BTC",
      lastBaselinePrice: 100,
      lastTriggeredAt: 123,
      lastTriggeredPrice: 105,
    });
    expect(mockedLocalStorage.getItem).toHaveBeenCalledWith("alert-state:BTC:1");
  });

  test("returns undefined when stored alert state is missing or invalid", async () => {
    mockedLocalStorage.getItem.mockResolvedValueOnce(undefined).mockResolvedValueOnce("not json");

    await expect(getAlertState("ETH", 1)).resolves.toBeUndefined();
    await expect(getAlertState("SOL", 1)).resolves.toBeUndefined();
  });

  test("saves serialized alert state under namespaced LocalStorage key", async () => {
    await saveAlertState({ symbol: "ETH", lastBaselinePrice: 200 }, 1);

    expect(mockedLocalStorage.setItem).toHaveBeenCalledWith(
      "alert-state:ETH:1",
      JSON.stringify({ symbol: "ETH", lastBaselinePrice: 200 })
    );
  });
});

test("returns undefined for incomplete or malformed alert state JSON", async () => {
  mockedLocalStorage.getItem
    .mockResolvedValueOnce(JSON.stringify({ symbol: "BTC" }))
    .mockResolvedValueOnce(JSON.stringify({ symbol: "BTC", lastBaselinePrice: "100" }))
    .mockResolvedValueOnce(JSON.stringify({ symbol: "BTC", lastBaselinePrice: null }));

  await expect(getAlertState("BTC", 1)).resolves.toBeUndefined();
  await expect(getAlertState("BTC", 1)).resolves.toBeUndefined();
  await expect(getAlertState("BTC", 1)).resolves.toBeUndefined();
});

test("stores state under a rule identity key including threshold", async () => {
  await saveAlertState({ symbol: "BTC", lastBaselinePrice: 200 }, 2);

  expect(mockedLocalStorage.setItem).toHaveBeenCalledWith(
    "alert-state:BTC:2",
    JSON.stringify({ symbol: "BTC", lastBaselinePrice: 200 })
  );
});

test("returns undefined when stored alert state belongs to a different symbol", async () => {
  mockedLocalStorage.getItem.mockResolvedValueOnce(JSON.stringify({ symbol: "ETH", lastBaselinePrice: 100 }));

  await expect(getAlertState("BTC", 1)).resolves.toBeUndefined();
});

test("returns parsed integer alert state from namespaced LocalStorage key", async () => {
  mockedLocalStorage.getItem.mockResolvedValueOnce(
    JSON.stringify({
      symbol: "BTC",
      lastBucket: 65,
      lastPrice: 65_820,
      lastTriggeredAt: 123,
      lastTriggeredPrice: 66_120,
      lastTriggeredBoundaryRanges: [{ startBucket: 66, endBucket: 66, triggeredAt: 123 }],
    })
  );

  await expect(getIntegerAlertState("BTC", 1000)).resolves.toEqual({
    symbol: "BTC",
    lastBucket: 65,
    lastPrice: 65_820,
    lastTriggeredAt: 123,
    lastTriggeredPrice: 66_120,
    lastTriggeredBoundaryRanges: [{ startBucket: 66, endBucket: 66, triggeredAt: 123 }],
  });
  expect(mockedLocalStorage.getItem).toHaveBeenCalledWith("integer-alert-state:BTC:1000");
});

test("saves serialized integer alert state under namespaced LocalStorage key", async () => {
  await saveIntegerAlertState({ symbol: "SOL", lastBucket: 14, lastPrice: 72 }, 5);

  expect(mockedLocalStorage.setItem).toHaveBeenCalledWith(
    "integer-alert-state:SOL:5",
    JSON.stringify({ symbol: "SOL", lastBucket: 14, lastPrice: 72 })
  );
});

test("returns undefined for malformed integer alert state JSON", async () => {
  mockedLocalStorage.getItem
    .mockResolvedValueOnce(JSON.stringify({ symbol: "BTC", lastBucket: 65 }))
    .mockResolvedValueOnce(JSON.stringify({ symbol: "BTC", lastBucket: "65", lastPrice: 65_820 }))
    .mockResolvedValueOnce(JSON.stringify({ symbol: "ETH", lastBucket: 65, lastPrice: 65_820 }));

  await expect(getIntegerAlertState("BTC", 1000)).resolves.toBeUndefined();
  await expect(getIntegerAlertState("BTC", 1000)).resolves.toBeUndefined();
  await expect(getIntegerAlertState("BTC", 1000)).resolves.toBeUndefined();
});
