import { drizzleAdapter } from "@better-auth/drizzle-adapter";
import { betterAuth } from "better-auth";
import { bearer } from "better-auth/plugins/bearer";
import type { Env } from "../config/env";
import type { Database } from "../db/client";
import { athletes } from "../db/schema";
import * as authSchema from "../db/schema/auth";

export function createAuth(env: Env, db: Database) {
  return betterAuth({
    appName: "hybrd",
    baseURL: env.BETTER_AUTH_URL,
    secret: env.BETTER_AUTH_SECRET,
    basePath: "/api/auth",
    database: drizzleAdapter(db, { provider: "pg", schema: authSchema }),
    trustedOrigins: [
      env.BETTER_AUTH_URL,
      ...env.TRUSTED_ORIGINS.split(",")
        .map((origin) => origin.trim())
        .filter(Boolean),
      ...(env.APPLE_CLIENT_ID ? ["https://appleid.apple.com"] : []),
    ],
    emailAndPassword: { enabled: env.DEV_AUTH_ENABLED },
    socialProviders:
      env.APPLE_CLIENT_ID && env.APPLE_CLIENT_SECRET
        ? {
            apple: {
              clientId: env.APPLE_CLIENT_ID,
              clientSecret: env.APPLE_CLIENT_SECRET,
              appBundleIdentifier: env.APPLE_APP_BUNDLE_IDENTIFIER,
            },
          }
        : {},
    plugins: [bearer()],
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
}
