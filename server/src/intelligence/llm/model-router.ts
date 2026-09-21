import type { Env } from "../../config/env";

// Only server configuration may select models. Implement quota/entitlement
// enforcement and invocation auditing before adding a provider transport.
export function configuredModel(
  env: Env,
  kind: "jev" | "llm",
): string | undefined {
  return kind === "jev" ? env.OPENROUTER_JEV_MODEL : env.OPENROUTER_LLM_MODEL;
}
