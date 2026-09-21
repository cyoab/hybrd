# Billing

Apple's official SignedDataVerifier checks certificate chains, signatures, bundle/environment and production app identity. The service additionally allowlists products and binds every purchase to the athlete UUID supplied as StoreKit appAccountToken. Restore submissions and signed V2 server notifications share the transactional entitlement updater.

Transactions/notification IDs deduplicate deliveries. Signed dates reject stale state. Renewal chains, grace, expiry, upgrade and revocation are handled; an older overlapping transaction cannot reactivate a revoked latest renewal. Reads and sync expire elapsed grants. Test verifier injection does not bypass verification in production wiring.
