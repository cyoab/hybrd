import type { Env } from "../config/env";

export type OtpMailer = (email: string, otp: string) => Promise<void>;

export function otpMessage(otp: string) {
  if (!/^\d{6}$/.test(otp))
    throw new Error("Invalid authentication code format.");
  return {
    subject: "Your hybrd sign-in code",
    text: `Your hybrd sign-in code is ${otp}.\n\nEnter it in the hybrd app. This code expires in 10 minutes and works once. Never share it. If you didn't request it, ignore this email.`,
    html: `<!doctype html><html lang="en"><body style="font-family:Arial,sans-serif;color:#18251e;padding:24px"><h1 style="font-size:24px">Sign in to hybrd</h1><p>Enter this code in the hybrd app:</p><p style="font-size:36px;font-weight:bold;letter-spacing:6px">${otp}</p><p>This code expires in 10 minutes and works once. Never share it.</p><p>If you didn't request it, ignore this email.</p></body></html>`,
  };
}

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
