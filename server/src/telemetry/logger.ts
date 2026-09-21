export type LogEntry = {
  event: string;
  requestId?: string;
  method?: string;
  route?: string;
  status?: number;
  durationMs?: number;
  errorType?: string;
  port?: number;
};

// Deliberately accept a small allowlist: no headers, tokens, query strings,
// request bodies, SQL errors, prompts, or athlete health data in HTTP logs.
export function log(entry: LogEntry) {
  console.info(
    JSON.stringify({ timestamp: new Date().toISOString(), ...entry }),
  );
}
