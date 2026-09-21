import { readFileSync } from "node:fs";
import {
  Environment,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
  SignedDataVerifier,
} from "@apple/app-store-server-library";
import { ApiError } from "../api/errors";
import type { Env } from "../config/env";
export interface AppleVerifier {
  available: boolean;
  transaction(jws: string): Promise<JWSTransactionDecodedPayload>;
  notification(jws: string): Promise<ResponseBodyV2DecodedPayload>;
  renewal(jws: string): Promise<JWSRenewalInfoDecodedPayload>;
}
export function appleVerifier(env: Env): AppleVerifier {
  let verifier: SignedDataVerifier | undefined;
  const available = Boolean(
    env.STOREKIT_BUNDLE_ID && env.STOREKIT_ROOT_CERTIFICATES,
  );
  function get() {
    if (!env.STOREKIT_ROOT_CERTIFICATES || !env.STOREKIT_BUNDLE_ID)
      throw new ApiError(
        503,
        "BILLING_NOT_CONFIGURED",
        "Apple signed-data verification is not configured.",
      );
    if (!verifier) {
      const roots = env.STOREKIT_ROOT_CERTIFICATES.split(",").map((path) =>
        readFileSync(path.trim()),
      );
      verifier = new SignedDataVerifier(
        roots,
        true,
        env.STOREKIT_ENVIRONMENT === "Production"
          ? Environment.PRODUCTION
          : Environment.SANDBOX,
        env.STOREKIT_BUNDLE_ID,
        env.STOREKIT_APP_APPLE_ID,
      );
    }
    return verifier;
  }
  async function verify<T>(
    fn: (v: SignedDataVerifier) => Promise<T>,
  ): Promise<T> {
    const v = get();
    try {
      return await fn(v);
    } catch {
      throw new ApiError(
        400,
        "INVALID_APPLE_SIGNATURE",
        "The Apple signed payload could not be verified.",
      );
    }
  }
  return {
    available,
    transaction: (jws) => verify((v) => v.verifyAndDecodeTransaction(jws)),
    notification: (jws) => verify((v) => v.verifyAndDecodeNotification(jws)),
    renewal: (jws) => verify((v) => v.verifyAndDecodeRenewalInfo(jws)),
  };
}
