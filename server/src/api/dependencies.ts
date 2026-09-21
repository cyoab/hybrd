import type {
  Bootstrap,
  DeviceInput,
  Entitlement,
  TrainingPolicy,
} from "./schemas";

export type AppEnv = { Variables: { requestId: string; authUserId: string } };

export interface AppDependencies {
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
