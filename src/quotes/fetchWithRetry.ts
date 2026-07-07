const DEFAULT_TIMEOUT_MS = 4500;
const DEFAULT_ATTEMPTS = 2;

export async function fetchJsonWithRetry<T>(url: string, options: { timeoutMs?: number; attempts?: number } = {}): Promise<T> {
  const attempts = options.attempts ?? DEFAULT_ATTEMPTS;
  let lastError: Error | undefined;

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await fetchWithTimeout(url, options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
      if (!response.ok) {
        throw new Error(`Request failed (${response.status} ${response.statusText || "HTTP error"}): ${url}`);
      }
      return (await response.json()) as T;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (attempt === attempts - 1) {
        throw lastError;
      }
    }
  }

  throw lastError ?? new Error(`Request failed: ${url}`);
}

function fetchWithTimeout(url: string, timeoutMs: number): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  return fetch(url, { signal: controller.signal }).finally(() => clearTimeout(timeout));
}
