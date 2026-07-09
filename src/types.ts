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

export type IntegerAlertRule = {
  symbol: string;
  step: number;
  enabled: boolean;
};

export type AlertState = {
  symbol: string;
  lastBaselinePrice: number;
  lastTriggeredAt?: number;
  lastTriggeredPrice?: number;
};

export type IntegerAlertBoundaryRange = {
  startBucket: number;
  endBucket: number;
  triggeredAt: number;
};

export type IntegerAlertState = {
  symbol: string;
  lastBucket: number;
  lastPrice: number;
  lastTriggeredAt?: number;
  lastTriggeredPrice?: number;
  lastTriggeredBoundaryRanges?: IntegerAlertBoundaryRange[];
};

export type ParsedAlertRules = {
  rules: AlertRule[];
  invalidTokens: string[];
};

export type ParsedIntegerAlertRules = {
  rules: IntegerAlertRule[];
  invalidTokens: string[];
};

export type AlertNotification = {
  symbol: string;
  title: string;
  message: string;
  movementPercent: number;
  thresholdPercent: number;
  crossedSteps: number;
  currentPrice: number;
  baselinePrice: number;
};

export type AlertEvaluation =
  | { kind: "initialize"; nextState: AlertState }
  | { kind: "none" }
  | { kind: "trigger"; notification: AlertNotification; nextState: AlertState };

export type IntegerAlertEvaluation =
  | { kind: "initialize"; nextState: IntegerAlertState }
  | { kind: "none" }
  | { kind: "update"; nextState: IntegerAlertState }
  | { kind: "trigger"; notification: AlertNotification; nextState: IntegerAlertState };
