import {
  index,
  jsonb,
  pgTable,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";
import { athletes } from "./foundation";
export const storekitTransactions = pgTable(
  "storekit_transactions",
  {
    transactionId: text("transaction_id").primaryKey(),
    athleteId: uuid("athlete_id")
      .notNull()
      .references(() => athletes.id, { onDelete: "cascade" }),
    originalTransactionId: text("original_transaction_id").notNull(),
    productId: text("product_id").notNull(),
    entitlementKey: text("entitlement_key").notNull(),
    environment: text("environment").notNull(),
    purchasedAt: timestamp("purchased_at", { withTimezone: true }).notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    graceUntil: timestamp("grace_until", { withTimezone: true }),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
    signedAt: timestamp("signed_at", { withTimezone: true }).notNull(),
    verifiedPayload: jsonb("verified_payload").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => [
    index("storekit_owner_idx").on(t.athleteId),
    index("storekit_original_idx").on(t.originalTransactionId),
  ],
);
export const appleNotifications = pgTable("apple_notifications", {
  id: uuid("id").primaryKey(),
  athleteId: uuid("athlete_id").references(() => athletes.id, {
    onDelete: "cascade",
  }),
  type: text("type").notNull(),
  receivedAt: timestamp("received_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
export const pushDeliveries = pgTable("push_deliveries", {
  id: uuid("id").primaryKey(),
  athleteId: uuid("athlete_id")
    .notNull()
    .references(() => athletes.id, { onDelete: "cascade" }),
  deviceId: uuid("device_id").notNull(),
  requestHash: text("request_hash").notNull(),
  status: text("status").notNull(),
  reason: text("reason"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});
