import { z } from "zod";

const optionalString = z.preprocess(
  (value) => (value === "" ? undefined : value),
  z.string().min(1).optional(),
);

const envSchema = z
  .object({
    NODE_ENV: z
      .enum(["development", "test", "production"])
      .default("development"),
    PORT: z.coerce.number().int().min(1).max(65535).default(3000),
    HOST: z.string().default("0.0.0.0"),
    DATABASE_URL: z.url().refine((v) => /^postgres(ql)?:/.test(v)),
    BETTER_AUTH_URL: z.url(),
    BETTER_AUTH_SECRET: z.string().min(32),
    TRUSTED_ORIGINS: z.string().default(""),
    DEV_AUTH_ENABLED: z
      .enum(["true", "false"])
      .default("false")
      .transform((v) => v === "true"),
    APPLE_CLIENT_ID: optionalString,
    APPLE_CLIENT_SECRET: optionalString,
    APPLE_APP_BUNDLE_IDENTIFIER: optionalString,
    GOOGLE_CLIENT_ID: optionalString,
    GOOGLE_CLIENT_SECRET: optionalString,
    GOOGLE_IOS_CLIENT_ID: optionalString,
    AUTH_EMAIL_TRANSPORT: z
      .enum(["disabled", "mailpit", "resend"])
      .default("disabled"),
    AUTH_EMAIL_FROM: z.email().default("signin@hybrd.test"),
    MAILPIT_URL: z.url().default("http://localhost:8025"),
    RESEND_API_KEY: optionalString,
    STRAVA_CLIENT_ID: optionalString,
    STRAVA_CLIENT_SECRET: optionalString,
    STRAVA_APP_RETURN_URL: z.url().default("hybrd://integrations/strava"),
    STRAVA_WEBHOOK_VERIFY_TOKEN: optionalString,
    STRAVA_WEBHOOK_SECRET: optionalString,
    STRAVA_WEBHOOK_SUBSCRIPTION_ID: optionalString,
    OPENROUTER_API_KEY: optionalString,
    OPENROUTER_JEV_MODEL: z.string().default("~typesafe/jev-latest"),
    OPENROUTER_LLM_MODEL: optionalString,
    AI_REQUIRED_ENTITLEMENT: z.string().min(1).max(64).default("pro"),
    AI_DECISIONS_PER_DAY: z.coerce
      .number()
      .int()
      .min(1)
      .max(10000)
      .default(100),
    AI_CHATS_PER_DAY: z.coerce.number().int().min(1).max(1000).default(30),
    AI_REQUESTS_PER_MINUTE: z.coerce.number().int().min(1).max(100).default(10),
    STOREKIT_BUNDLE_ID: optionalString,
    STOREKIT_APP_APPLE_ID: z.preprocess(
      (v) => (v === "" ? undefined : v),
      z.coerce.number().int().positive().optional(),
    ),
    STOREKIT_ENVIRONMENT: z.enum(["Sandbox", "Production"]).default("Sandbox"),
    STOREKIT_ROOT_CERTIFICATES: optionalString,
    STOREKIT_PRODUCTS: z.string().default("{}"),
    APNS_KEY_ID: optionalString,
    APNS_TEAM_ID: optionalString,
    APNS_PRIVATE_KEY_PATH: optionalString,
    APNS_TOPIC: optionalString,
  })
  .superRefine((env, ctx) => {
    if (Boolean(env.STRAVA_CLIENT_ID) !== Boolean(env.STRAVA_CLIENT_SECRET))
      ctx.addIssue({
        code: "custom",
        path: ["STRAVA_CLIENT_ID"],
        message: "Set Strava client ID and secret together.",
      });
    if (env.STRAVA_CLIENT_ID && !/^\d+$/.test(env.STRAVA_CLIENT_ID))
      ctx.addIssue({
        code: "custom",
        path: ["STRAVA_CLIENT_ID"],
        message: "Expected a numeric Strava application ID.",
      });
    if (
      !["https:", "hybrd:"].includes(
        new URL(env.STRAVA_APP_RETURN_URL).protocol,
      )
    )
      ctx.addIssue({
        code: "custom",
        path: ["STRAVA_APP_RETURN_URL"],
        message: "Use an HTTPS universal link or hybrd app URL.",
      });
    const webhook = [
      env.STRAVA_WEBHOOK_VERIFY_TOKEN,
      env.STRAVA_WEBHOOK_SECRET,
      env.STRAVA_WEBHOOK_SUBSCRIPTION_ID,
    ];
    if (
      webhook.some(Boolean) &&
      (!env.STRAVA_WEBHOOK_VERIFY_TOKEN ||
        !env.STRAVA_WEBHOOK_SECRET ||
        !env.STRAVA_CLIENT_ID ||
        (env.STRAVA_WEBHOOK_SECRET?.length ?? 0) < 32)
    )
      ctx.addIssue({
        code: "custom",
        path: ["STRAVA_WEBHOOK_SECRET"],
        message:
          "Configure Strava webhook verification and a path secret of at least 32 characters with an enabled Strava provider. Add the subscription ID after verification.",
      });
    if (env.NODE_ENV === "production") {
      if (env.AUTH_EMAIL_TRANSPORT === "mailpit")
        ctx.addIssue({
          code: "custom",
          path: ["AUTH_EMAIL_TRANSPORT"],
          message: "Mailpit is forbidden in production.",
        });
      if (env.DEV_AUTH_ENABLED)
        ctx.addIssue({
          code: "custom",
          path: ["DEV_AUTH_ENABLED"],
          message: "Development authentication is forbidden in production.",
        });
      if (!env.BETTER_AUTH_URL.startsWith("https://"))
        ctx.addIssue({
          code: "custom",
          path: ["BETTER_AUTH_URL"],
          message: "Production requires HTTPS.",
        });
      if (
        env.BETTER_AUTH_SECRET.startsWith("replace-") ||
        env.BETTER_AUTH_SECRET.startsWith("test-")
      )
        ctx.addIssue({
          code: "custom",
          path: ["BETTER_AUTH_SECRET"],
          message: "Set a unique production secret.",
        });
    }
    if (
      (env.GOOGLE_CLIENT_ID ||
        env.GOOGLE_CLIENT_SECRET ||
        env.GOOGLE_IOS_CLIENT_ID) &&
      !(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET)
    )
      ctx.addIssue({
        code: "custom",
        path: ["GOOGLE_CLIENT_ID"],
        message:
          "Set Google client ID and secret together; the iOS client ID is optional.",
      });
    if (
      env.AUTH_EMAIL_TRANSPORT === "resend" &&
      (!env.RESEND_API_KEY || env.AUTH_EMAIL_FROM.endsWith(".test"))
    )
      ctx.addIssue({
        code: "custom",
        path: ["AUTH_EMAIL_TRANSPORT"],
        message:
          "Resend requires RESEND_API_KEY and a sender on your verified domain.",
      });
    try {
      const products = JSON.parse(env.STOREKIT_PRODUCTS);
      if (
        !products ||
        Array.isArray(products) ||
        typeof products !== "object" ||
        !Object.values(products).every(
          (v) => typeof v === "string" && v.length > 0 && v.length <= 64,
        )
      )
        throw new Error();
    } catch {
      ctx.addIssue({
        code: "custom",
        path: ["STOREKIT_PRODUCTS"],
        message: "Expected an object mapping product IDs to entitlement keys.",
      });
    }
    for (const [name, fields] of [
      ["STOREKIT", [env.STOREKIT_BUNDLE_ID, env.STOREKIT_ROOT_CERTIFICATES]],
      [
        "APNS",
        [
          env.APNS_KEY_ID,
          env.APNS_TEAM_ID,
          env.APNS_PRIVATE_KEY_PATH,
          env.APNS_TOPIC,
        ],
      ],
    ] as const) {
      if (fields.some(Boolean) && !fields.every(Boolean))
        ctx.addIssue({
          code: "custom",
          path: [name],
          message: `Set all ${name} integration fields together.`,
        });
    }
    if (
      env.STOREKIT_BUNDLE_ID &&
      env.STOREKIT_ENVIRONMENT === "Production" &&
      !env.STOREKIT_APP_APPLE_ID
    )
      ctx.addIssue({
        code: "custom",
        path: ["STOREKIT_APP_APPLE_ID"],
        message: "Production verification requires the numeric app ID.",
      });
    const apple = [
      env.APPLE_CLIENT_ID,
      env.APPLE_CLIENT_SECRET,
      env.APPLE_APP_BUNDLE_IDENTIFIER,
    ];
    if (apple.some(Boolean) && !apple.every(Boolean))
      ctx.addIssue({
        code: "custom",
        path: ["APPLE_CLIENT_ID"],
        message: "Set all three Apple provider variables, or leave all empty.",
      });
  });

export type Env = z.infer<typeof envSchema>;

export function readEnv(
  source: Record<string, string | undefined> = process.env,
): Env {
  const result = envSchema.safeParse(source);
  if (!result.success) {
    // Never serialize the input: it contains credentials.
    throw new Error(
      `Invalid environment: ${result.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ")}`,
    );
  }
  return result.data;
}
