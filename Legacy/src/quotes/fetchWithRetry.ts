import { execFile } from "child_process";

const DEFAULT_TIMEOUT_MS = 4500;
const DEFAULT_ATTEMPTS = 2;

type Fetcher = (url: string, timeoutMs: number, signal?: AbortSignal) => Promise<Response>;
type CurlRunner = (url: string, timeoutMs: number, proxyArgs: string[]) => Promise<{ status: number; body: string }>;
type ScutilRunner = () => Promise<string>;

type FetchJsonOptions = {
  timeoutMs?: number;
  attempts?: number;
  useCurl?: boolean;
  fetcher?: Fetcher;
  curlRunner?: CurlRunner;
  scutilRunner?: ScutilRunner;
};

export async function fetchJsonWithRetry<T>(url: string, options: FetchJsonOptions = {}): Promise<T> {
  const attempts = options.attempts ?? DEFAULT_ATTEMPTS;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  let lastError: Error | undefined;

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await fetchJson<T>(url, timeoutMs, options.fetcher ?? fetchWithTimeout);
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (attempt === attempts - 1) {
        if (options.useCurl) {
          return await fetchJsonWithCurl<T>(
            url,
            timeoutMs,
            options.curlRunner ?? runCurl,
            options.scutilRunner ?? runScutilProxy
          );
        }
        throw lastError;
      }
    }
  }

  throw lastError ?? new Error(`Request failed: ${url}`);
}

async function fetchJson<T>(url: string, timeoutMs: number, fetcher: Fetcher): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetcher(url, timeoutMs, controller.signal);
    if (!response.ok) {
      throw new Error(`Request failed (${response.status} ${response.statusText || "HTTP error"}): ${url}`);
    }
    // ponytail: race body parsing against abort so a stalled/injected body
    // promise that ignores the signal still rejects at the timeout boundary.
    return await Promise.race([response.json() as Promise<T>, rejectOnAbort(controller.signal, timeoutMs)]);
  } finally {
    clearTimeout(timeout);
  }
}

function rejectOnAbort(signal: AbortSignal, timeoutMs: number): Promise<never> {
  return new Promise((_resolve, reject) => {
    signal.addEventListener("abort", () => {
      reject(new Error(`Request timed out after ${timeoutMs}ms`));
    });
  });
}

async function fetchJsonWithCurl<T>(
  url: string,
  timeoutMs: number,
  curlRunner: CurlRunner,
  scutilRunner: ScutilRunner
): Promise<T> {
  const proxyArgs = getHttpsProxyArgs(await scutilRunner());
  const response = await curlRunner(url, timeoutMs, proxyArgs);
  if (response.status < 200 || response.status >= 300) {
    throw new Error(`Request failed (${response.status} HTTP error): ${url}`);
  }
  return JSON.parse(response.body) as T;
}

function fetchWithTimeout(url: string, _timeoutMs: number, signal?: AbortSignal): Promise<Response> {
  return fetch(url, signal ? { signal } : {});
}

function getHttpsProxyArgs(scutilOutput: string): string[] {
  const enabled = scutilOutput.match(/HTTPSEnable\s*:\s*1/);
  const proxy = scutilOutput.match(/HTTPSProxy\s*:\s*([^\n]+)/)?.[1]?.trim();
  const port = scutilOutput.match(/HTTPSPort\s*:\s*(\d+)/)?.[1]?.trim();
  if (!enabled || !proxy || !port) {
    return [];
  }
  return ["--proxy", `http://${proxy}:${port}`];
}

function runScutilProxy(): Promise<string> {
  return new Promise((resolve) => {
    execFile("/usr/sbin/scutil", ["--proxy"], (error, stdout) => {
      resolve(error ? "" : stdout);
    });
  });
}

function runCurl(url: string, timeoutMs: number, proxyArgs: string[]): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    execFile(
      "/usr/bin/curl",
      [
        "--silent",
        "--show-error",
        "--location",
        "--max-time",
        String(Math.ceil(timeoutMs / 1000)),
        ...proxyArgs,
        "--write-out",
        "\n%{http_code}",
        url,
      ],
      { maxBuffer: 10 * 1024 * 1024 },
      (error, stdout, stderr) => {
        if (error) {
          reject(new Error(stderr || error.message));
          return;
        }
        const separator = stdout.lastIndexOf("\n");
        const body = separator >= 0 ? stdout.slice(0, separator) : stdout;
        const status = Number(separator >= 0 ? stdout.slice(separator + 1) : 0);
        resolve({ status, body });
      }
    );
  });
}
