import type { Quote } from "#/types";

export type QuoteFetchResult = {
  quotes: Record<string, Quote>;
  missingSymbols: string[];
  errors: string[];
  updatedAt: number;
};
