const PRICE_FORMATTERS = [
  { max: 1, digits: 4 },
  { max: 100, digits: 3 },
  { max: 1000, digits: 2 },
] as const;

export function formatPrice(price: number): string {
  const digits = PRICE_FORMATTERS.find((formatter) => Math.abs(price) < formatter.max)?.digits ?? 0;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(price);
}

export function formatPercent(value: number): string {
  const sign = value > 0 ? "+" : "";
  return `${sign}${value.toFixed(2)}%`;
}

export function formatAge(updatedAt: number, now: number): string {
  const ageSeconds = Math.max(0, Math.round((now - updatedAt) / 1000));
  if (ageSeconds < 60) {
    return `${ageSeconds}s ago`;
  }
  return `${Math.floor(ageSeconds / 60)}m ago`;
}
