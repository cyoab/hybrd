import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from "node:crypto";

const key = (secret: string) =>
  createHash("sha256").update(`hybrd:strava:tokens:${secret}`).digest();
export const digest = (value: string) =>
  createHash("sha256").update(value).digest("hex");
export function seal(
  secret: string,
  owner: string,
  tokens: { access_token: string; refresh_token: string },
) {
  const iv = randomBytes(12),
    cipher = createCipheriv("aes-256-gcm", key(secret), iv);
  cipher.setAAD(Buffer.from(owner));
  const ciphertext = Buffer.concat([
    cipher.update(
      JSON.stringify({
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
      }),
      "utf8",
    ),
    cipher.final(),
  ]);
  return [
    "v1",
    iv.toString("base64url"),
    cipher.getAuthTag().toString("base64url"),
    ciphertext.toString("base64url"),
  ].join(".");
}
export function unseal(
  secret: string,
  owner: string,
  sealed: string,
): { access_token: string; refresh_token: string } {
  const [version, iv, tag, data] = sealed.split(".");
  if (version !== "v1" || !iv || !tag || !data)
    throw new Error("Invalid Strava token envelope");
  const cipher = createDecipheriv(
    "aes-256-gcm",
    key(secret),
    Buffer.from(iv, "base64url"),
  );
  cipher.setAAD(Buffer.from(owner));
  cipher.setAuthTag(Buffer.from(tag, "base64url"));
  return JSON.parse(
    Buffer.concat([
      cipher.update(Buffer.from(data, "base64url")),
      cipher.final(),
    ]).toString("utf8"),
  );
}
