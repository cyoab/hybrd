import type { Env } from "../../config/env";

// Clients never select a model; provider calls are gated by the gateway service.
export function configuredModel(
  env: Env,
  kind: "jev" | "llm",
): string | undefined {
  return kind === "jev" ? env.OPENROUTER_JEV_MODEL : env.OPENROUTER_LLM_MODEL;
}
