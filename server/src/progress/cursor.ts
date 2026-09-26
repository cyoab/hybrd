import { createHmac, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { ApiError } from "../api/errors";

const Cursor = z
  .object({
    scope: z.string(),
    generation: z.string().uuid(),
    expires: z.number(),
    after: z.string().max(200),
  })
  .strict();
export function cursors(secret: string) {
  const signature = (value: string) =>
    createHmac("sha256", secret)
      .update(`progress-cursor-v1:${value}`)
      .digest("base64url");
  return {
    encode(input: z.infer<typeof Cursor>) {
      const body = Buffer.from(JSON.stringify(input)).toString("base64url");
      return `${body}.${signature(body)}`;
    },
    decode(
      value: string | undefined,
      scope: string,
      generation: string,
      now: Date,
    ) {
      if (!value) return null;
      let decoded: z.infer<typeof Cursor>;
      try {
        const [body, sig, extra] = value.split(".");
        if (!body || !sig || extra) throw new Error("Invalid cursor");
        const expected = Buffer.from(signature(body)),
          received = Buffer.from(sig);
        if (
          expected.length !== received.length ||
          !timingSafeEqual(expected, received)
        )
          throw new Error("Invalid signature");
        decoded = Cursor.parse(
          JSON.parse(Buffer.from(body, "base64url").toString()),
        );
        if (decoded.scope !== scope) throw new Error("Wrong scope");
      } catch {
        throw new ApiError(
          400,
          "INVALID_PROGRESS_CURSOR",
          "The cursor does not belong to this query. Start a new page sequence.",
        );
      }
      if (decoded.generation !== generation || decoded.expires <= now.getTime())
        throw new ApiError(
          409,
          "PROGRESS_CURSOR_EXPIRED",
          "Progress changed. Reload the first page.",
        );
      return decoded.after;
    },
  };
}
