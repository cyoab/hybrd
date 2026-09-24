import type { billingServices } from "../billing/service";
import type { readCatalog } from "../catalog/service";
import type { intelligenceServices } from "../intelligence/service";
import type { onboardingServices } from "../onboarding/service";
import type { progressServices } from "../progress/service";
import type { stravaServices } from "../strava/service";
import type { syncServices } from "../sync/service";
import type {
  Bootstrap,
  DeviceInput,
  Entitlement,
  TrainingPolicy,
} from "./schemas";

export type AppEnv = { Variables: { requestId: string; authUserId: string } };

export interface AppDependencies {
  onboarding: ReturnType<typeof onboardingServices>;
  strava: ReturnType<typeof stravaServices>;
  progress: ReturnType<typeof progressServices>;
  billing: ReturnType<typeof billingServices>;
  intelligence: ReturnType<typeof intelligenceServices>;
  sync: ReturnType<typeof syncServices>;
  catalog(): ReturnType<typeof readCatalog>;
  deleteAccount(authUserId: string, headers: Headers): Promise<void>;
  exportAccount(authUserId: string): Promise<Record<string, unknown>>;
  checkDatabase(): Promise<void>;
  authenticate(headers: Headers): Promise<string | null>;
  handleAuth(request: Request): Promise<Response>;
  bootstrap(authUserId: string, deviceId?: string): Promise<Bootstrap>;
  trainingPolicy(): Promise<TrainingPolicy | null>;
  registerDevice(
    authUserId: string,
    deviceId: string,
    input: DeviceInput,
  ): Promise<void>;
  revokeDevice(authUserId: string, deviceId: string): Promise<void>;
  entitlements(authUserId: string): Promise<Entitlement[]>;
}
