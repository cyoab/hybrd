# Implementation status and next steps

This scaffold follows the supplied architecture's module boundaries and its Phase 1 foundation order. It does not claim to implement the product requirements yet.

| Area | Implemented now | Next work |
| --- | --- | --- |
| Runtime | Bun, Hono, Zod, configuration, errors, lifecycle | Feature-specific endpoints as needed |
| Authentication | Better Auth, Drizzle adapter, bearer sessions, provisioning hook, optional Apple config | Exercise native Apple integration with real credentials |
| Athletes | Identity, preferences for presentation, bootstrap | Goals, training preferences, availability, baseline/context snapshots and sync |
| Database | 11 foundation tables, SQL migration and snapshot | Relational training domain from architecture section 9 |
| Sync | Tables, provisional envelopes, 501 routes | Typed handlers, transactional idempotency, concurrency, feed pagination and reconstruction |
| Plans | Module boundary and invariants | Blocks, immutable versions, prescriptions and audit changes |
| Workouts | Module boundary and invariants | Catalog, results, sets, segments, provenance/deduplication |
| Policy | Published policy retrieval, ETags, development fixture | Reviewed versioned policy schema/publication and compatibility |
| AI | Decision registry, compact request schemas, server model configuration, 501 routes | OpenRouter transport, quotas, entitlements, validation, audit/cost records, SSE |
| Billing | Stored entitlement reads, 501 transaction route | Verified Apple transactions and lifecycle handling |
| Notifications | Idempotent device registration and revocation | APNs provider integration when a use case requires it |
| Account deletion | Explicit 501 route | Product retention decision and implementation |
| Operations | Compose, health checks, migrations, tests, production image, Railway config | Actual Railway provisioning, secrets, monitoring/backups |

The full proposed data model is not pre-created as empty tables. Add each relational aggregate with its ownership checks, constraints, and transactional sync handler. Keep immutable plan content and executed results physically separated. Do not use a generic JSONB entity table as a substitute for the training schema.

Sync is the next backend milestone. See `server/src/sync/README.md`, particularly the distinction between sequence allocation and commit order, initial athlete backfill, request-hash validation, and plan-head concurrency. The existing sync bookkeeping tables are unused until those handlers exist.

Avoid extending production behavior through development fixtures: seed policy v1 only disables features, creates no test athlete, and grants no entitlement. Remote AI credentials alone never enable a feature. All placeholder routes return errors rather than simulated success.

The initial documents have been preserved unchanged. The backend does not implement Swift training algorithms or add infrastructure the documents defer.
