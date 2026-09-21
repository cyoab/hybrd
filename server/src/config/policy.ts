import { createHash } from "node:crypto";

// Development fixture: no unreviewed training thresholds are shipped as policy.
export const developmentPolicy = {
  features: {
    sync: false,
    remoteDecisions: false,
    remoteCoach: false,
    billing: false,
  },
};

export function policyChecksum(config: Record<string, unknown>): string {
  return `sha256:${createHash("sha256").update(JSON.stringify(config)).digest("hex")}`;
}
