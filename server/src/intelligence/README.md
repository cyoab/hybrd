# Intelligence

The Jev decision registry, server-selected model configuration, request contracts, and authenticated routes are scaffolded. Both routes return 501 and make no network requests, including when credentials are set.

Before enabling a gateway, implement entitlement checks, per-athlete quotas, idempotent invocation records, provider timeouts, bounded compact context, response validation, and cost/audit metadata. Do not accept client-selected models or arbitrary Jev prompts. Confirm the current Jev request protocol with OpenRouter rather than assuming it behaves like a generative chat model.

The coach needs a versioned context contract and SSE response contract before client integration. Model output can only propose actions; it never writes plans. Prompts and raw health streams must not enter telemetry.
