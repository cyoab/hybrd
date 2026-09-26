import type { OpenAPIHono } from "@hono/zod-openapi";
import { z } from "@hono/zod-openapi";
import type { AppEnv } from "../api/dependencies";

const email = z.string().trim().toLowerCase().pipe(z.email().max(254));
export const SendOtpSchema = z
  .object({ email, type: z.literal("sign-in") })
  .strict();
export const VerifyOtpSchema = z
  .object({
    email,
    otp: z.string().regex(/^\d{6}$/),
    name: z.string().trim().max(100).optional(),
  })
  .strict();
export const NativeSocialSchema = z
  .object({
    provider: z.enum(["google", "apple"]),
    idToken: z
      .object({
        token: z.string().min(1).max(16_384),
        nonce: z.string().min(16).max(256),
        user: z
          .object({
            name: z
              .object({
                firstName: z.string().max(100),
                lastName: z.string().max(100),
              })
              .partial()
              .optional(),
          })
          .strict()
          .optional(),
      })
      .strict(),
  })
  .strict();
const UserSchema = z.object({
  id: z.string(),
  email: z.email(),
  emailVerified: z.boolean(),
  name: z.string(),
  image: z.string().nullable().optional(),
  createdAt: z.iso.datetime(),
  updatedAt: z.iso.datetime(),
});
const SessionSchema = z.object({ token: z.string(), user: UserSchema });
const ErrorSchema = z.object({ code: z.string(), message: z.string() });
const json = (schema: z.ZodType) => ({ "application/json": { schema } });

// Runtime stays inside Better Auth so its origin/CSRF/session protections apply.
export function registerAuthContract(app: OpenAPIHono<AppEnv>) {
  const common = { tags: ["Authentication"], security: [] };
  app.openAPIRegistry.registerPath({
    ...common,
    method: "get",
    path: "/api/auth/methods",
    operationId: "getAuthMethods",
    responses: {
      200: {
        description: "Configured sign-in options; no credentials are exposed.",
        content: json(
          z.object({
            google: z.boolean(),
            apple: z.boolean(),
            emailOtp: z.boolean(),
            otp: z.object({
              length: z.literal(6),
              expiresInSeconds: z.literal(600),
              resendAfterSeconds: z.literal(60),
              maxSendsPerHour: z.literal(3),
            }),
          }),
        ),
      },
    },
  });
  for (const [path, operationId, schema, response] of [
    [
      "/api/auth/email-otp/send-verification-otp",
      "sendSignInCode",
      SendOtpSchema,
      z.object({ success: z.literal(true) }),
    ],
    [
      "/api/auth/sign-in/email-otp",
      "verifySignInCode",
      VerifyOtpSchema,
      SessionSchema,
    ],
    [
      "/api/auth/sign-in/social",
      "signInWithNativeProvider",
      NativeSocialSchema,
      SessionSchema.extend({ redirect: z.literal(false) }),
    ],
  ] as const) {
    app.openAPIRegistry.registerPath({
      ...common,
      method: "post",
      path,
      operationId,
      description: path.endsWith("social")
        ? "Native Google/Apple ID-token exchange. Include the nonce supplied to the provider SDK. Better Auth also supports its browser redirect flow on this path."
        : "Works for both first-time registration and returning sign-in.",
      request: { body: { required: true, content: json(schema) } },
      responses: {
        200: {
          description:
            "Success. Store a returned session token in Keychain and use Authorization: Bearer <token>.",
          content: json(response),
        },
        400: {
          description:
            "Invalid input, incorrect/expired/consumed code, or unavailable provider.",
          content: json(ErrorSchema),
        },
        401: {
          description: "Invalid identity token.",
          content: json(ErrorSchema),
        },
        403: {
          description:
            "Unverified identity, disallowed origin, or too many code attempts.",
          content: json(ErrorSchema),
        },
        429: {
          description: "Rate limited; honor Retry-After in seconds.",
          headers: { "Retry-After": { schema: { type: "string" } } },
          content: json(ErrorSchema),
        },
        503: {
          description:
            "Email delivery unavailable. A new request is needed after the cooldown.",
          content: json(ErrorSchema),
        },
      },
    });
  }
}
