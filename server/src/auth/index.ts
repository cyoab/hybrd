import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { APIError, createAuthMiddleware } from "better-auth/api";
import { bearer } from "better-auth/plugins/bearer";
import { emailOTP } from "better-auth/plugins/email-otp";
import { and, eq } from "drizzle-orm";
import type { Env } from "../config/env";
import type { Database } from "../db/client";
import { athletes } from "../db/schema";
import * as authSchema from "../db/schema/auth";
import { NativeSocialSchema, SendOtpSchema, VerifyOtpSchema } from "./contract";
import { createOtpMailer, type OtpMailer } from "./email";
import { authDigest, reserveOtpSend } from "./otp-limit";

export function createAuth(
  env: Env,
  db: Database,
  options: { mailer?: OtpMailer } = {},
) {
  const mailer = options.mailer ?? createOtpMailer(env);
  const failedDeliveries = new WeakSet<object>();
  const auth = betterAuth({
    appName: "hybrd",
    baseURL: env.BETTER_AUTH_URL,
    secret: env.BETTER_AUTH_SECRET,
    basePath: "/api/auth",
    // Exercise the same origin protections in tests as in deployed environments.
    advanced: { disableOriginCheck: false },
    database: drizzleAdapter(db, { provider: "pg", schema: authSchema }),
    trustedOrigins: [
      env.BETTER_AUTH_URL,
      ...env.TRUSTED_ORIGINS.split(",")
        .map((origin) => origin.trim())
        .filter(Boolean),
      ...(env.APPLE_CLIENT_ID ? ["https://appleid.apple.com"] : []),
    ],
    emailAndPassword: { enabled: env.DEV_AUTH_ENABLED },
    user: {
      validateUserInfo: ({ user, source }) => {
        if (source.method === "oauth" && user.emailVerified !== true)
          return {
            error: "UNVERIFIED_PROVIDER_EMAIL",
            errorDescription: "A verified provider email is required.",
          };
      },
    },
    account: {
      accountLinking: {
        enabled: true,
        trustedProviders: [],
        requireLocalEmailVerified: true,
      },
    },
    socialProviders: {
      ...(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET
        ? {
            google: {
              clientId: [
                env.GOOGLE_CLIENT_ID,
                ...(env.GOOGLE_IOS_CLIENT_ID ? [env.GOOGLE_IOS_CLIENT_ID] : []),
              ],
              clientSecret: env.GOOGLE_CLIENT_SECRET,
            },
          }
        : {}),
      ...(env.APPLE_CLIENT_ID &&
      env.APPLE_CLIENT_SECRET &&
      env.APPLE_APP_BUNDLE_IDENTIFIER
        ? {
            apple: {
              clientId: env.APPLE_CLIENT_ID,
              clientSecret: env.APPLE_CLIENT_SECRET,
              appBundleIdentifier: env.APPLE_APP_BUNDLE_IDENTIFIER,
              audience: [env.APPLE_CLIENT_ID, env.APPLE_APP_BUNDLE_IDENTIFIER],
              // Apple may omit email on later authorizations. Recover it only
              // from an existing account bound to the verified Apple subject.
              mapProfileToUser: async (profile) => {
                if (profile.email) return {};
                const [owner] = await db
                  .select({
                    email: authSchema.user.email,
                    emailVerified: authSchema.user.emailVerified,
                    name: authSchema.user.name,
                  })
                  .from(authSchema.account)
                  .innerJoin(
                    authSchema.user,
                    eq(authSchema.user.id, authSchema.account.userId),
                  )
                  .where(
                    and(
                      eq(authSchema.account.providerId, "apple"),
                      eq(authSchema.account.accountId, profile.sub),
                    ),
                  )
                  .limit(1);
                return owner ?? {};
              },
            },
          }
        : {}),
    },
    plugins: [
      bearer(),
      emailOTP({
        otpLength: 6,
        expiresIn: 600,
        allowedAttempts: 5,
        disableSignUp: false,
        storeOTP: {
          hash: async (otp) =>
            authDigest(env.BETTER_AUTH_SECRET, `otp-code:${otp}`),
        },
        resendStrategy: "rotate",
        rateLimit: { window: 60, max: 10 },
        sendVerificationOTP: async ({ email, otp }, ctx) => {
          try {
            await mailer(email, otp);
          } catch {
            if (ctx) failedDeliveries.add(ctx.context);
            await db
              .delete(authSchema.verification)
              .where(
                eq(authSchema.verification.identifier, `sign-in-otp-${email}`),
              );
            // Better Auth catches delivery callback exceptions. Surface failure
            // in the after hook instead of falsely telling the app it was sent.
          }
        },
      }),
    ],
    disabledPaths: [
      "/email-otp/check-verification-otp",
      "/email-otp/verify-email",
      "/email-otp/request-password-reset",
      "/forget-password/email-otp",
      "/email-otp/reset-password",
      "/email-otp/request-email-change",
      "/email-otp/change-email",
    ],
    hooks: {
      after: createAuthMiddleware(async (ctx) => {
        if (failedDeliveries.delete(ctx.context))
          throw new APIError(
            "SERVICE_UNAVAILABLE",
            {
              code: "EMAIL_DELIVERY_UNAVAILABLE",
              message:
                "We couldn't send a code. Please try again after the cooldown.",
            },
            { "Retry-After": "60" },
          );
      }),
      before: createAuthMiddleware(async (ctx) => {
        const sending = ctx.path === "/email-otp/send-verification-otp";
        const verifying = ctx.path === "/sign-in/email-otp";
        if (sending || verifying) {
          if (env.AUTH_EMAIL_TRANSPORT === "disabled")
            throw new APIError("SERVICE_UNAVAILABLE", {
              code: "EMAIL_DELIVERY_UNAVAILABLE",
              message: "Email sign-in is not configured.",
            });
          const parsed = (sending ? SendOtpSchema : VerifyOtpSchema).safeParse(
            ctx.body,
          );
          if (!parsed.success)
            throw new APIError("BAD_REQUEST", {
              code: "INVALID_AUTH_INPUT",
              message: "Enter a valid email and six-digit code when required.",
            });
          ctx.body = parsed.data;
          if (sending) {
            const retry = await reserveOtpSend(
              db,
              env.BETTER_AUTH_SECRET,
              parsed.data.email,
            );
            if (retry) {
              throw new APIError(
                "TOO_MANY_REQUESTS",
                {
                  code: "OTP_SEND_RATE_LIMITED",
                  message: "Please wait before requesting another code.",
                },
                { "Retry-After": String(retry) },
              );
            }
            // Invalidate the previous code before rotation. The unique constraint
            // prevents more than one usable code for the same address.
            await db
              .delete(authSchema.verification)
              .where(
                eq(
                  authSchema.verification.identifier,
                  `sign-in-otp-${parsed.data.email}`,
                ),
              );
          }
        }
        if (ctx.path === "/sign-in/social" && ctx.body?.idToken) {
          const parsed = NativeSocialSchema.safeParse(ctx.body);
          if (!parsed.success)
            throw new APIError("BAD_REQUEST", {
              code: "INVALID_AUTH_INPUT",
              message:
                "Provide a Google or Apple identity token and its nonce.",
            });
          ctx.body = parsed.data;
        }
        return { context: { body: ctx.body } };
      }),
    },
    // Memory rate limits fit the initial single-instance control plane.
    rateLimit: { enabled: env.NODE_ENV !== "test", storage: "memory" },
    databaseHooks: {
      user: {
        create: {
          after: async (user) => {
            await db
              .insert(athletes)
              .values({ authUserId: user.id })
              .onConflictDoNothing();
          },
        },
      },
    },
  });
  return {
    ...auth,
    handler: (request: Request): Promise<Response> => {
      if (
        request.method === "GET" &&
        new URL(request.url).pathname === "/api/auth/methods"
      )
        return Promise.resolve(
          Response.json(
            {
              google: Boolean(env.GOOGLE_CLIENT_ID),
              apple: Boolean(env.APPLE_CLIENT_ID),
              emailOtp: env.AUTH_EMAIL_TRANSPORT !== "disabled",
              otp: {
                length: 6,
                expiresInSeconds: 600,
                resendAfterSeconds: 60,
                maxSendsPerHour: 3,
              },
            },
            { headers: { "Cache-Control": "no-store" } },
          ),
        );
      return auth.handler(request);
    },
  };
}
