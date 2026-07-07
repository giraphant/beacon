export type Quote = {
  symbol: string;
  name: string;
  price: number;
  source: string;
  updatedAt: number;
  high24h?: number;
  low24h?: number;
  change24h?: number;
};

export type AlertRule = {
  symbol: string;
  thresholdPercent: number;
  enabled: boolean;
};

export type AlertState = {
  symbol: string;
  lastBaselinePrice: number;
  lastTriggeredAt?: number;
  lastTriggeredPrice?: number;
};

export type ParsedAlertRules = {
  rules: AlertRule[];
  invalidTokens: string[];
};
