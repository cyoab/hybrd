# Training agent API — first backend delivery

Implemented contract, 25 September 2026. This guide supersedes the **proposed** run/memory API where the routes below differ. The [architecture plan](ai-agent-implementation-plan.md) remains the roadmap. The backend owns `server/`, migrations, OpenAPI and these examples; the parallel iOS task owns native implementation.

## Available now and next phases

This delivery implements durable **read-only training chat and workout analysis**, typed server data tools, Jev input/output scope checks, curated citation objects, bounded prompt context, cache/usage accounting, cancellation, recoverable SSE, and user-managed memory. Plan generation, plan mutations/Undo, automatic memory extraction, native recording commands and additional sensor-packet upload are **not enabled or implemented by this delivery**. `create_plan` and `modify_plan` are reserved task values and return `409 AGENT_TASK_NOT_ENABLED` without model work. Do not implement UI success states for those tasks yet.

The next backend phase is the complete plan blueprint/compiler and draft persistence, followed by authorized edits and Undo. iOS prescription fidelity and capability negotiation remain activation requirements; they do not prevent backend development in parallel.

## Enabling development

Apply the checked-in migration with `make migrate`. The worker runs inside the existing API process; Docker Compose still needs only API and PostgreSQL as persistent dev services. Existing `/v1/intelligence/*` behavior is preserved.

Set the following environment values, then recreate the API container to apply them:

```dotenv
AGENT_ENABLED=true
OPENROUTER_API_KEY=YOUR_SERVER_ONLY_KEY
OPENROUTER_JEV_MODEL=YOUR_TESTED_JEV_ROUTE
AGENT_MODEL=YOUR_TESTED_TOOL_CAPABLE_MODEL
AGENT_CACHE_MODE=automatic
AGENT_SCOPE_CONFIDENCE=0.8
AGENT_MAX_GENERATIVE_CALLS=4
```

`AGENT_MODEL` falls back to `OPENROUTER_LLM_MODEL` if omitted. `automatic` targets endpoints with automatic prompt caching; use `ephemeral` only with an endpoint tested to support `cache_control`. Stable prefixes and an opaque conversation session ID are sent consistently. Provider fallback is disabled for this path. Cold starts, cache expiry and provider thresholds still cause misses; the usage ledger preserves unknown values when the provider omits cache/cost information. [OpenRouter caching contract](https://openrouter.ai/docs/guides/best-practices/prompt-caching).

The agent defaults off. Live rollout also requires configured model/classifier, published policy enabling `remoteCoach`, `cloudAiConsent:true`, a registered installation and an active/grace coaching entitlement (`pro` by default). Scope thresholds and model quality require live evaluation before production enablement. The implementation tests inject providers and do not send athlete data to a live model.

## Endpoints

All routes require the usual bearer session and return the existing error envelope. Responses are private/no-store. UUID idempotency keys belong in the header, not the JSON body.

| Route | Contract |
| --- | --- |
| `GET /v1/agent/capabilities` | Environment/policy/provider availability and supported task flags. Consent and entitlement remain separate checks. |
| `POST /v1/agent/runs` | Requires `Idempotency-Key: UUID`. Returns `202 AgentRun` after durable reservation, before any provider call. |
| `GET /v1/agent/runs/{id}` | Recover current status and final structured artifact. |
| `GET /v1/agent/runs/{id}/events` | SSE with optional `Last-Event-ID: decimal-string`. |
| `POST /v1/agent/runs/{id}/cancel` | Idempotent cancellation; returns current run. A completed run stays completed. |
| `GET /v1/agent/memories` | Up to 20 user-managed entries, including expiry and revisions. |
| `PUT /v1/agent/memories/{id}` | Create with `expectedRevision:null`; replace with the current revision. The caller allocates the memory UUID. |
| `DELETE /v1/agent/memories/{id}` | Requires `If-Match: revision` as an unquoted decimal string. |

No `/continue`, `/undo`, native-command or analysis-input upload route exists yet. Clarification currently ends a run with a `clarification` artifact; send a new run in the same thread for the answer.

Schemas are generated in [OpenAPI](../contracts/openapi.yaml). Shared examples use synthetic IDs:

- [Chat request](../contracts/examples/agent-run.json)
- [Analysis request](../contracts/examples/agent-analysis.json)
- [Completed analysis](../contracts/examples/agent-run-succeeded.json)

For analysis, send the canonical `workoutResultId` and exact `expectedWorkoutRevision` after normal sync. The server rereads owned data. Other tasks must omit/null both fields. The result's original prescription, segments and actual strength sets are available to the agent; precise GPS and nonexistent sensor traces are not. Measurements carry stable references of the form `resultId@revision:metricKey`. `artifactStale:true` means the analyzed result has since changed or been deleted; label that explanation as historical and offer a new analysis.

## iOS request and recovery flow

1. Fetch capabilities after authentication/bootstrap. Persist the request JSON and a fresh UUID idempotency key before sending. Use `threadId:null` for a new conversation; the first run atomically creates a canonical coach thread/user message.
2. Store the returned `id` and `threadId`. If the POST response is lost, resend the **same body and key**; it returns the original run, including terminal status. Changing the body with that key returns `IDEMPOTENCY_KEY_REUSED`. One active run is allowed per conversation, across new and legacy coaching APIs.
3. Open the events endpoint with bearer authorization. Store the event cursor separately from the canonical sync cursor. Events have `id`, `runId`, `type`, `data` and `createdAt`; SSE `id` is the same decimal sequence. Deduplicate durably by `(runId,id)`.
4. `status` and `tool_status` describe progress. On `artifact_ready`/`completed`, GET the run and render the typed artifact. SSE contains no provisional model prose or executable prescriptions. Canonical threads/messages restore through normal sync; agent artifacts are deliberately excluded from that feed to preserve older decoders.
5. The connection rotates after at most 25 seconds, with periodic `heartbeat` events carrying no ID. Reconnect using the last durable ID; a normal end-of-stream is not a failed task. A terminal run closes its stream after replay. Use GET status after suspension/relaunch rather than creating another run.
6. Event history lasts seven days. `AGENT_EVENT_REPLAY_EXPIRED` requires restoring GET status; do not keep retrying an old cursor. `AGENT_EVENT_CURSOR_AHEAD` means the cursor belongs to different/incorrect local state. Midstream `error` events have no ID and carry only `errorCode`; refresh auth or reconnect as appropriate.
7. Cancel through the dedicated route and display its returned status. A request already sent to a provider may still incur usage; cancellation prevents its late answer from publishing. Stop listeners and clear account-scoped in-memory state on sign-out/account switch.

Run statuses are `queued`, `running`, `succeeded`, `failed`, `cancelled`, `indeterminate`. **Indeterminate is terminal:** a worker lost an in-flight provider response or the provider transport outcome is uncertain. Never automatically create a new billable attempt. Display the condition and allow an explicit retry with a new idempotency key.

## Artifacts, science and scope

Render `content`, `observations`, `interpretations`, `limitations`, `recommendations` and resolved `citations` separately where useful. Observations cite actual metric references. Interpretations may cite evidence IDs resolved in the artifact's citation array. Citation URLs/titles/claim summaries come from a server-owned registry; the model cannot supply arbitrary citation URLs. Citation identity validation does not prove scientific entailment; that requires the planned model/evidence evaluation.

Artifacts have kind `answer`, `workout_analysis`, `scope_redirect` or `clarification`. These are successful responses, not network errors. Input classification can restrict a mixed request to its training portion; output classification blocks unrelated answers. Deterministic authorization, tool allowlists, input schemas and ownership apply independently of Jev confidence. No data tool can write a plan or perform a native action.

## Memory behavior

Memory is explicitly athlete-managed in this phase. There is no automatic extraction, inferred medical state or hidden preference mutation. The combined limit is 20 entries/5,000 characters; active entries form a stable prompt snapshot. Temporary constraints can expire. Training preferences remain canonical in the normal profile; a memory note does not itself change those records or workouts.

Editing/forgetting memory cancels pending runs with `MEMORY_CONTEXT_CHANGED`, clears persisted prompt checkpoints and establishes a new conversation-context boundary. Older transcript text is excluded from subsequent model prompts so a removed fact is not silently recalled from history. Historical conversation/analysis records remain viewable; forgetting a memory is not deletion of those records or of workout history. Account export/deletion includes agent runs and memory; account deletion cascades and delayed provider responses cannot recreate them.

## Limits and operational behavior

- At most four generative calls per run (configurable downward), eight read-tool calls, bounded model output and a 96 KiB checkpoint. Jev input and final-output checks are separate bounded calls.
- Per-athlete daily/minute run quotas use existing AI chat/minute settings; at most two pending runs per athlete. API rate limiting also applies.
- Every paid step reserves an invocation before dispatch. Successful steps checkpoint atomically with events. Expired in-flight leases terminate as indeterminate rather than reissuing the request.
- Usage records include total input, cached reads, cache writes, output/reasoning tokens, latency and reported cost. No raw provider error body is exposed or logged.
- Expired event records are pruned automatically; operational request/checkpoint payloads expire after 30 days for terminal runs. Final conversation/analysis artifacts remain account data until account deletion.

Stable errors worth representing: `AGENT_DISABLED`, `AGENT_TASK_NOT_ENABLED`, `INTELLIGENCE_NOT_CONFIGURED`, `AI_CONSENT_REQUIRED`, `ENTITLEMENT_REQUIRED`, `DEVICE_UNAVAILABLE`, `THREAD_BUSY`, `AI_QUOTA_EXCEEDED`, `AGENT_CONTEXT_CHANGED`, `WORKOUT_REVISION_CONFLICT`, `AGENT_BUDGET_EXHAUSTED`, `AGENT_PROVIDER_OUTCOME_UNKNOWN`, `MEMORY_REVISION_CONFLICT` and `MEMORY_BUDGET_EXCEEDED`.

## Parallel iOS work

Integrate the connected Coach/run adapter and typed read-only artifact cards against this contract now. Continue the [native prescription work](ai-ios-harness-review.md): deterministic repeat identities, distance-ended runs, full strength targets, canonical catalog IDs, offline outbox reconciliation and pinned active-session snapshots. Keep plan-create/edit UI gated by task capabilities until the next backend contract is available. Do not infer plan success from assistant prose.
