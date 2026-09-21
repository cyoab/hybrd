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
    if (env.NODE_ENV === "production") {
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
