import type { Env } from "../config/env";
import { otpMessage } from "./emails/otp-template";

export { otpMessage } from "./emails/otp-template";

export type OtpMailer = (email: string, otp: string) => Promise<void>;

// Errors deliberately omit provider responses, recipients, codes and credentials.
export function createOtpMailer(
  env: Env,
  fetcher: typeof fetch = fetch,
): OtpMailer {
  return async (email, otp) => {
    if (env.AUTH_EMAIL_TRANSPORT === "disabled")
      throw new Error("Email delivery unavailable.");
    const message = otpMessage(otp);
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Idempotency-Key": `auth-otp/${crypto.randomUUID()}`,
    };
    const body = JSON.stringify({
      from: `hybrd <${env.AUTH_EMAIL_FROM}>`,
      to: [email],
      ...message,
    });
    // Reuse this request's idempotency key if delivery has an uncertain outcome.
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const response = await fetcher("https://api.resend.com/emails", {
          method: "POST",
          headers,
          body,
          signal: AbortSignal.timeout(10_000),
        });
        await response.body?.cancel();
        if (response.ok) return;
        if (response.status !== 429 && response.status < 500) break;
      } catch {
        /* Retry once using the same idempotency key. */
      }
      if (attempt === 0) await Bun.sleep(250);
    }
    throw new Error("Email delivery unavailable.");
  };
}
