export const INSTRUMENTS: Record<string, { name: string }> = {
  BTC: { name: "Bitcoin" },
  ETH: { name: "Ethereum" },
  BNB: { name: "BNB" },
  SOL: { name: "Solana" },
  XRP: { name: "XRP" },
  JUP: { name: "Jupiter" },
  JTO: { name: "Jito" },
  SUI: { name: "Sui" },
  JLP: { name: "Jupiter Perps LP" },
  HYPE: { name: "Hyperliquid" },
  AAPL: { name: "Apple" },
  AMZN: { name: "Amazon" },
  COIN: { name: "Coinbase" },
  GOOG: { name: "Google" },
  GOOGL: { name: "Google" },
  HOOD: { name: "Robinhood" },
  INTC: { name: "Intel" },
  META: { name: "Meta" },
  MSTR: { name: "MicroStrategy" },
  NVDA: { name: "Nvidia" },
  QQQ: { name: "Invesco QQQ" },
  SPY: { name: "SPDR S&P 500" },
  TSLA: { name: "Tesla" },
  TSM: { name: "TSMC" },
  XPL: { name: "Plasma" },
};

export function getInstrumentName(symbol: string) {
  return INSTRUMENTS[symbol]?.name ?? symbol;
}
