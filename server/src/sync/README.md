# Sync

Typed aggregate mutation/pull contracts are in `schemas.ts`; handlers in `mutations.ts`; transaction orchestration in `service.ts`. Each mutation uses an athlete lock, global mutation-ID lock, a savepoint for domain writes, a durable request hash/result and change-feed entries in one transaction. Batch siblings commit independently.

Pull hydrates current canonical aggregates under the same athlete lock, avoiding sequence/commit gaps. It can return newer revisions for old events. New installations begin at zero. Acknowledgements advance monotonically. Tombstones, feed and mutation ledger are retained to support offline devices. See `docs/ios-handoff.md` for client behavior.
