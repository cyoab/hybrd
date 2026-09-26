# Push notifications

The APNs adapter signs ES256 provider tokens, uses HTTP/2 and targets each opted-in installation's environment. Operator sends accept an idempotency UUID and one of two data-minimizing payloads: sync hint or generic coach-ready alert. Delivery metadata is retained, and invalid-token responses clear only the token actually attempted. A pending or uncertain delivery is never silently retried.

Local scheduled training reminders remain an iOS responsibility. No public send endpoint, job queue or background worker is introduced.
