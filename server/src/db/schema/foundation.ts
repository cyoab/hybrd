import { sql } from "drizzle-orm";
import {
  bigint,
  boolean,
  check,
  index,
  integer,
  jsonb,
  pgTable,
  primaryKey,
  smallint,
  text,
  time,
  timestamp,
  unique,
  uuid,
} from "drizzle-orm/pg-core";
import { user } from "./auth";

export const athletes = pgTable(
  "athletes",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    authUserId: text("auth_user_id")
      .notNull()
      .unique()
      .references(() => user.id),
    timezone: text("timezone").notNull().default("UTC"),
    locale: text("locale").notNull().default("en"),
    distanceUnit: text("distance_unit").notNull().default("km"),
    loadUnit: text("load_unit").notNull().default("kg"),
    weekStartsOn: smallint("week_starts_on").notNull().default(1),
    trainingDayBoundary: time("training_day_boundary"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (t) => [
    check("athletes_distance_unit", sql`${t.distanceUnit} in ('km', 'mi')`),
    check("athletes_load_unit", sql`${t.loadUnit} in ('kg', 'lb')`),
    check("athletes_week_starts_on", sql`${t.weekStartsOn} between 1 and 7`),
    check("athletes_revision_positive", sql`${t.revision} > 0`),
  ],
);

export const trainingPolicyVersions = pgTable(
  "training_policy_versions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    version: integer("version").notNull().unique(),
    schemaVersion: integer("schema_version").notNull(),
    status: text("status").notNull().default("draft"),
    config: jsonb("config").$type<Record<string, unknown>>().notNull(),
    checksum: text("checksum").notNull(),
    minimumAppVersion: text("minimum_app_version"),
    publishedAt: timestamp("published_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => [
    check(
      "policy_status",
      sql`${t.status} in ('draft', 'published', 'retired')`,
    ),
    check(
      "policy_versions_positive",
      sql`${t.version} > 0 and ${t.schemaVersion} > 0`,
    ),
  ],
);

export const deviceInstallations = pgTable(
  "device_installations",
  {
    id: uuid("id").primaryKey(),
    athleteId: uuid("athlete_id")
      .notNull()
      .references(() => athletes.id),
    platform: text("platform").notNull().default("ios"),
    appVersion: text("app_version").notNull(),
    osVersion: text("os_version"),
    pushToken: text("push_token"),
    pushEnabled: boolean("push_enabled").notNull().default(false),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
  },
  (t) => [
    index("devices_athlete_idx").on(t.athleteId),
    unique("devices_id_athlete_unique").on(t.id, t.athleteId),
    check("devices_platform", sql`${t.platform} = 'ios'`),
  ],
);

export const entitlements = pgTable(
  "entitlements",
  {
    athleteId: uuid("athlete_id")
      .notNull()
      .references(() => athletes.id),
    entitlementKey: text("entitlement_key").notNull(),
    status: text("status").notNull(),
    validUntil: timestamp("valid_until", { withTimezone: true }),
    source: text("source").notNull(),
    revision: bigint("revision", { mode: "bigint" }).notNull().default(sql`1`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => [
    primaryKey({ columns: [t.athleteId, t.entitlementKey] }),
    check(
      "entitlements_status",
      sql`${t.status} in ('active', 'grace', 'expired', 'revoked')`,
    ),
  ],
);
