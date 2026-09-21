# Billing

Reading authenticated entitlement records is implemented. StoreKit transaction submission is an explicit 501 scaffold; submitting a signed string cannot grant access.

Implement Apple's signed transaction verification, bundle/application/environment checks, account binding, subscription lifecycle handling, and deduplication by verified transaction ID before writing transactions or entitlements. Publish entitlement changes into the sync feed in the same transaction. No Stripe dependency is needed for this StoreKit-first architecture.
