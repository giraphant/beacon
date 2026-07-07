import { formatAge, formatPercent, formatPrice } from "./format";

describe("formatPrice", () => {
  it("formats compact source-native prices", () => {
    expect(formatPrice(103245.18)).toBe("$103,245");
    expect(formatPrice(421.456)).toBe("$421.46");
    expect(formatPrice(0.123456)).toBe("$0.1235");
  });
});

describe("formatPercent", () => {
  it("formats signed percentage values", () => {
    expect(formatPercent(3.245)).toBe("+3.25%");
    expect(formatPercent(-1)).toBe("-1.00%");
  });
});

describe("formatAge", () => {
  it("formats seconds and minutes", () => {
    expect(formatAge(1_000, 12_000)).toBe("11s ago");
    expect(formatAge(1_000, 181_000)).toBe("3m ago");
  });
});
