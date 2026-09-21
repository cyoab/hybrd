# Workouts

Scaffold for the exercise/equipment catalog, completed workout envelopes, running summaries and segments, strength exercises and sets, and external activity provenance (architecture sections 9.3 and 9.7–9.10). Schema and mutation handlers are the next implementation phase.

Prescriptions and results must be separate tables. Store meters, seconds, decimal kilograms, explicit athlete training dates, and the IANA time zone at execution. IDs are client-generated UUIDs. Match a result to the exact historical prescription; substitutions preserve both intended and performed exercises.

Future mutation handlers must validate athlete ownership through every parent, preserve partial/skipped outcomes, deduplicate provider identities, and write revisions and deletion tombstones transactionally. Keep raw GPS/HR streams in HealthKit and calculate analytics locally.
