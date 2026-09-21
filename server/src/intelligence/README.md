# Intelligence

The gateway enforces explicit profile consent, effective entitlement, published policy, persistent daily/minute quotas and idempotency before calling a provider. Only server configuration chooses models. Jev uses OpenRouter's Decisions API with typed contexts and server-owned criteria. The coach uses bounded history/context and strict structured output. Invalid output rolls back canonical writes.

External requests run outside database transactions. Account deletion, consent withdrawal and plan-head changes are rechecked on completion. A pending/uncertain attempt is never reissued automatically. Canonical decisions, messages and proposals sync; telemetry contains usage/cost/model metadata, not full prompts. Coach proposals never mutate plans directly. JSON is default; SSE emits one validated complete event.
