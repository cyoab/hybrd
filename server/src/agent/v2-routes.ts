import { createRoute, type OpenAPIHono, z } from "@hono/zod-openapi";
import type { AppDependencies, AppEnv } from "../api/dependencies";
import { errorResponse, protectedErrors, security } from "../api/schemas";
import { AgentEvent } from "./schemas";
import {
  ActionReceipt,
  AgentRunInputV2,
  AgentRunV2,
  AnalysisPacket,
  DeviceChallenge,
  DeviceManifest,
  LearnedMemory,
  MemorySettings,
  UndoInput,
} from "./v2-schemas";
import {
  AckInput,
  AgentCapabilitiesV2,
  ClaimInput,
  ManifestReceipt,
  PlanningContextView,
} from "./v2-wire";

export function registerAgentV2Routes(
  app: OpenAPIHono<AppEnv>,
  deps: AppDependencies,
) {
  app.openAPIRegistry.register("AgentEvent", AgentEvent);
  const errors = {
    ...protectedErrors,
    403: errorResponse,
    404: errorResponse,
    409: errorResponse,
    503: errorResponse,
  };
  const params = z.object({ id: z.string().uuid() }),
    keys = z.object({ "idempotency-key": z.string().uuid() });
  const register = (
    method: "get" | "post" | "put" | "delete",
    path: string,
    operationId: string,
    response: z.ZodType,
    handler: (
      user: string,
      args: {
        id?: string;
        body: unknown;
        key: string;
        query: Record<string, string>;
      },
    ) => Promise<unknown>,
    options: {
      body?: z.ZodType;
      id?: boolean;
      key?: boolean;
      query?: z.ZodObject;
      status?: 200 | 202;
      description: string;
    },
  ) => {
    const responses: Record<
      number,
      {
        description: string;
        content: { "application/json": { schema: z.ZodType } };
      }
    > = {
      ...errors,
      [options.status ?? 200]: {
        description: options.description,
        content: { "application/json": { schema: response } },
      },
    };
    app.openapi(
      createRoute({
        method,
        path: `/v1/agent/v2${path}`,
        operationId,
        tags: ["AgentV2"],
        security,
        request: {
          ...(options.id ? { params } : {}),
          ...(options.key ? { headers: keys } : {}),
          ...(options.query ? { query: options.query } : {}),
          ...(options.body
            ? {
                body: {
                  required: true,
                  content: { "application/json": { schema: options.body } },
                },
              }
            : {}),
        },
        responses,
      }),
      async (c) => {
        const result = await handler(c.get("authUserId"), {
          id: c.req.param("id"),
          body: options.body ? await c.req.json() : undefined,
          key: c.req.header("idempotency-key") ?? "",
          query: c.req.query(),
        });
        return c.json(
          response.parse(result) as Record<string, unknown>,
          options.status ?? 200,
        );
      },
    );
  };
  register(
    "post",
    "/device-challenges/{id}/claim",
    "claimAgentDeviceChallenge",
    DeviceChallenge,
    (u, a) => deps.agent.claimChallengeV2(u, a.id!, a.key, a.body),
    {
      id: true,
      key: true,
      body: ClaimInput,
      description:
        "Immediately before local execution, atomically claim the pending command using its exact device/recording/digest. A claimed action cannot be cancelled remotely; retry only with the same key and never execute a claimed action twice.",
    },
  );
  register(
    "post",
    "/device-challenges/{id}/cancel",
    "cancelAgentDeviceChallenge",
    DeviceChallenge,
    (u, a) => deps.agent.cancelChallengeV2(u, a.id!),
    {
      id: true,
      description:
        "Cancel a pending native challenge. Claimed or acknowledged commands remain unchanged. A cancelled pending challenge cannot subsequently be claimed.",
    },
  );
  register(
    "delete",
    "/exercise-rules/{id}",
    "removeAgentExerciseRule",
    z.object({ removed: z.literal(true) }),
    (u, a) => deps.agent.removeRuleV2(u, a.id!, a.query.expectedRevision ?? ""),
    {
      id: true,
      query: z.object({ expectedRevision: z.string().regex(/^[1-9][0-9]*$/) }),
      description:
        "Remove an explicit recurring exercise rule with its current revision. Existing prescriptions remain immutable; future generation stops applying the rule.",
    },
  );
  register(
    "get",
    "/capabilities",
    "getAgentCapabilitiesV2",
    AgentCapabilitiesV2,
    (u) => deps.agent.capabilitiesV2(u),
    {
      description:
        "Explicit v2 negotiation; unnegotiated v1 capabilities stay unchanged.",
    },
  );
  register(
    "put",
    "/device-manifest",
    "putAgentDeviceManifest",
    ManifestReceipt,
    (u, a) => deps.agent.putManifest(u, a.body),
    {
      body: DeviceManifest,
      description:
        "Registers distinct phone/Watch capabilities for 24 hours. Each installation must belong to this athlete.",
    },
  );
  register(
    "get",
    "/planning-context",
    "getAgentPlanningContext",
    PlanningContextView,
    (u, a) => deps.agent.contextV2(u, a.query.trainingBlockId ?? null),
    {
      query: z.object({ trainingBlockId: z.string().uuid().optional() }),
      description:
        "After draining the local outbox, fetch current revisions/token. Token includes profile, preferences, availability, equipment, results, baseline, rules, blocks and policy. Relative dates use the athlete timezone/training day.",
    },
  );
  register(
    "post",
    "/runs",
    "createAgentRunV2",
    AgentRunV2,
    (u, a) => deps.agent.createV2(u, a.key, a.body),
    {
      body: AgentRunInputV2,
      key: true,
      status: 202,
      description:
        "Durable idempotent v2 run. Mutation scope and device capabilities are required for writes; no provider call occurs on the request path.",
    },
  );
  register(
    "get",
    "/runs",
    "listAgentRunsV2",
    z.object({
      runs: z.array(AgentRunV2),
      nextBefore: z.string().uuid().nullable(),
    }),
    (u, a) => deps.agent.listV2(u, a.query.before ?? null),
    {
      query: z.object({ before: z.string().uuid().optional() }),
      description:
        "Restore rich history across installations. Pages contain at most 20 runs; nextBefore is an owned run ID.",
    },
  );
  register(
    "get",
    "/runs/{id}",
    "getAgentRunV2",
    AgentRunV2,
    (u, a) => deps.agent.getV2(u, a.id!),
    {
      id: true,
      description:
        "Canonical action receipt, Undo status, learned memory IDs and device challenge. Use existing /v1/agent/runs/{id}/events SSE for durable progress then refetch here.",
    },
  );
  register(
    "get",
    "/requests/{id}",
    "lookupAgentRequestV2",
    AgentRunV2,
    (u, a) => deps.agent.lookupV2(u, a.id!),
    {
      id: true,
      description:
        "Lookup by original Idempotency-Key without starting or replaying provider work.",
    },
  );
  register(
    "post",
    "/requests/{id}/cancel",
    "cancelAgentRequestV2",
    AgentRunV2,
    (u, a) => deps.agent.lookupV2(u, a.id!, true),
    {
      id: true,
      description:
        "Cancel by original key, never create missing work. A committed action remains committed; use Undo separately.",
    },
  );
  register(
    "post",
    "/actions/{id}/apply",
    "applyAgentDraft",
    ActionReceipt,
    (u, a) => deps.agent.applyV2(u, a.id!, a.key, a.body),
    {
      id: true,
      key: true,
      body: UndoInput,
      description:
        "Accept a validated draft after sync and fresh context checks. No additional model call; idempotent activation with a verified action receipt.",
    },
  );
  register(
    "post",
    "/actions/{id}/undo",
    "undoAgentAction",
    ActionReceipt,
    (u, a) => deps.agent.undoV2(u, a.id!, a.key, a.body),
    {
      id: true,
      key: true,
      body: UndoInput,
      description:
        "Idempotent compensating edit, valid seven days. Requires fresh context/current head; rejects conflicting later edits or recorded sessions. Preserves unrelated changes.",
    },
  );
  register(
    "put",
    "/analysis-packet",
    "putAgentAnalysisPacket",
    z.object({ checksum: z.string(), status: z.literal("stored") }),
    (u, a) => deps.agent.packetV2(u, a.body),
    {
      body: AnalysisPacket,
      description:
        "Whole immutable packet per owned result revision; 256 KiB, 1000 HR samples, 2000 interval/split/lap boundaries. Exact retries deduplicate by canonical SHA-256. No GPS. No chunk uploads: aggregate explicitly with coverage omissions.",
    },
  );
  const settings = z.object({ enabled: z.boolean(), revision: z.string() });
  register(
    "get",
    "/memory-settings",
    "getAgentMemorySettings",
    settings,
    (u) => deps.agent.settingsV2(u),
    {
      description:
        "Automatic learning defaults off independently of cloud coaching consent.",
    },
  );
  register(
    "put",
    "/memory-settings",
    "putAgentMemorySettings",
    settings,
    (u, a) => deps.agent.settingsV2(u, a.body),
    {
      body: MemorySettings,
      description:
        "Explicit opt-in/revocation with revision check. Revocation erases learned memories and invalidates pending prompt context.",
    },
  );
  register(
    "get",
    "/memories",
    "listAgentMemoriesV2",
    z.object({ memories: z.array(LearnedMemory) }),
    (u) => deps.agent.memoriesV2(u),
    {
      description:
        "Visible memory with source run/message, exact quote, confidence, revision and expiry. Existing PUT/DELETE memory endpoints edit/forget and invalidate pending context.",
    },
  );
  register(
    "post",
    "/device-challenges/{id}/ack",
    "acknowledgeAgentDeviceAction",
    DeviceChallenge,
    (u, a) => deps.agent.ackV2(u, a.id!, a.key, a.body),
    {
      id: true,
      key: true,
      body: AckInput,
      description:
        "Acknowledge exact device/recording/action digest within 120 seconds. Native must verify local state, permission and foreground consent before executing. Idempotent result; pending does not mean executed.",
    },
  );
}
