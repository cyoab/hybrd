# Sync

The envelope schemas, routes, ledger, change log, and device state tables are scaffolded. Both endpoints return `501 NOT_IMPLEMENTED`; the bootstrap capability is `available: false`. The client must keep its outbox entries until real per-mutation acknowledgements are implemented.

Before enabling sync:

1. Add discriminated payload schemas and explicit handlers for each domain entity; reject unknown types and operations.
2. Require a registered, non-revoked device owned by the authenticated athlete.
3. Apply each mutation, request hash, deterministic replay result, and change-feed entry in one transaction. Reusing an ID with a different body is a conflict, never a replay.
4. Enforce base revisions, parent ownership, immutable accepted plans, and plan-head compare-and-swap. A batch needs per-mutation failures rather than partial untracked writes.
5. Serialize writers per athlete (for example with a transaction advisory lock) **before allocating change sequences**. PostgreSQL identity values alone do not guarantee commit order; a pull cursor must never skip an earlier uncommitted write.
6. Implement consistent, bounded pull pagination, payload hydration, and tombstones. Advance only after applying returned changes locally.
7. Backfill the provisioned athlete and current entitlement when implementing initial sync, so a new phone can reconstruct all canonical state.

Cursors and revisions are decimal strings on the wire to preserve 64-bit precision.
