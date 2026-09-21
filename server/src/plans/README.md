# Plans

`schemas.ts` defines immutable plan aggregates. `service.ts` persists relational running/strength prescriptions, validates owned context, diffs logical sessions and activates a draft only against the expected active head. Activation records explicit acceptance and before/after audit rows. Completed prescriptions remain unchanged across revisions. Coach proposals only apply with a separately synced and explicitly activated plan.

The local iOS engine owns feasibility, progression and candidate generation. Backend validation protects structure, ownership, history and concurrency.
