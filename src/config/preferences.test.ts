import {
  parseAlertRulesText,
  parseCoinDisplayText,
  parseIntegerAlertCooldownMinutes,
  parseIntegerAlertRulesText,
  parseSymbolsText,
} from "./preferences";

describe("parseSymbolsText", () => {
  it("normalizes space, comma, and vertical-bar separated symbols", () => {
    expect(parseSymbolsText("btc, eth | NVDA  qqq")).toEqual(["BTC", "ETH", "NVDA", "QQQ"]);
  });

  it("deduplicates symbols while preserving first occurrence order", () => {
    expect(parseSymbolsText("BTC eth btc ETH sol")).toEqual(["BTC", "ETH", "SOL"]);
  });
});

describe("parseAlertRulesText", () => {
  it("parses symbol threshold pairs", () => {
    expect(parseAlertRulesText("BTC:2 NVDA:1.5 sol:1")).toEqual({
      rules: [
        { symbol: "BTC", thresholdPercent: 2, enabled: true },
        { symbol: "NVDA", thresholdPercent: 1.5, enabled: true },
        { symbol: "SOL", thresholdPercent: 1, enabled: true },
      ],
      invalidTokens: [],
    });
  });

  it("skips invalid tokens and keeps valid rules", () => {
    expect(parseAlertRulesText("BTC:2 nope ETH:-1 SOL:0 JUP:1.25")).toEqual({
      rules: [
        { symbol: "BTC", thresholdPercent: 2, enabled: true },
        { symbol: "JUP", thresholdPercent: 1.25, enabled: true },
      ],
      invalidTokens: ["nope", "ETH:-1", "SOL:0"],
    });
  });

  it("lets the last duplicate rule win", () => {
    expect(parseAlertRulesText("BTC:2 ETH:1 BTC:3")).toEqual({
      rules: [
        { symbol: "ETH", thresholdPercent: 1, enabled: true },
        { symbol: "BTC", thresholdPercent: 3, enabled: true },
      ],
      invalidTokens: [],
    });
  });
});

describe("parseCoinDisplayText", () => {
  it("splits title symbols before the pipe from dropdown quote symbols", () => {
    expect(parseCoinDisplayText("BTC ETH | NVDA QQQ")).toEqual({
      titleSymbols: ["BTC", "ETH"],
      quoteSymbols: ["BTC", "ETH", "NVDA", "QQQ"],
    });
  });

  it("uses all configured symbols in the title when no pipe is present", () => {
    expect(parseCoinDisplayText("btc, eth nvda")).toEqual({
      titleSymbols: ["BTC", "ETH", "NVDA"],
      quoteSymbols: ["BTC", "ETH", "NVDA"],
    });
  });
});

describe("parseIntegerAlertCooldownMinutes", () => {
  it("parses non-negative minute values and defaults invalid values to 10", () => {
    expect(parseIntegerAlertCooldownMinutes("0")).toBe(0);
    expect(parseIntegerAlertCooldownMinutes("5.5")).toBe(5.5);
    expect(parseIntegerAlertCooldownMinutes("bad")).toBe(10);
    expect(parseIntegerAlertCooldownMinutes(undefined)).toBe(10);
  });
});

describe("parseIntegerAlertRulesText", () => {
  it("parses symbol step pairs", () => {
    expect(parseIntegerAlertRulesText("BTC:1000 sol:5 JUP:0.05")).toEqual({
      rules: [
        { symbol: "BTC", step: 1000, enabled: true },
        { symbol: "SOL", step: 5, enabled: true },
        { symbol: "JUP", step: 0.05, enabled: true },
      ],
      invalidTokens: [],
    });
  });

  it("skips invalid tokens and keeps valid integer rules", () => {
    expect(parseIntegerAlertRulesText("BTC:1000 nope ETH:-1 SOL:0 JUP:0.05")).toEqual({
      rules: [
        { symbol: "BTC", step: 1000, enabled: true },
        { symbol: "JUP", step: 0.05, enabled: true },
      ],
      invalidTokens: ["nope", "ETH:-1", "SOL:0"],
    });
  });

  it("lets the last duplicate integer rule win", () => {
    expect(parseIntegerAlertRulesText("BTC:1000 ETH:5 BTC:500")).toEqual({
      rules: [
        { symbol: "ETH", step: 5, enabled: true },
        { symbol: "BTC", step: 500, enabled: true },
      ],
      invalidTokens: [],
    });
  });
});
