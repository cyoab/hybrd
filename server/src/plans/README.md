# Plans

Scaffold for canonical training blocks, immutable plan versions, exact running and strength prescriptions, planning context snapshots, and plan-change audit records (architecture sections 9.4–9.6 and 9.11).

Implement relational schema and sync handlers together. The current migration deliberately includes only the foundation tables; it does not yet create the training domain.

Required behavior:

- Preserve `logical_workout_id` across versions and the exact prescribed instance for completed results.
- Freeze activated content. Change the accepted head with a transaction and compare-and-swap against the expected prior version.
- Validate ownership of every nested relationship, not just the outer plan.
- Persist policy/input snapshots and visible acceptance of material changes.
- Keep candidate generation, scheduling, progression, and training calculations in iOS.

Do not add server plan-generation or CRUD routes; accepted local plans enter through sync.
