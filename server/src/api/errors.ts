import type { ContentfulStatusCode } from "hono/utils/http-status";

export class ApiError extends Error {
  constructor(
    public readonly status: ContentfulStatusCode,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export function notImplemented(feature: string): never {
  throw new ApiError(
    501,
    "NOT_IMPLEMENTED",
    `${feature} is scaffolded and is not available yet.`,
  );
}
