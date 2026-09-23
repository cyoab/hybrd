# Authentication integration

Google, Apple and email OTP all create a verified account on first sign-in and return a session for an existing account on later sign-ins. The backend provisions one athlete per user. There is no separate passwordless registration endpoint or magic link. Swift UI/SDK integration belongs to the iOS agent.

## Client contract

`GET /api/auth/methods` is public and returns `google`, `apple`, `emailOtp` availability booleans and OTP timing/length metadata. Only offer configured methods. These four login endpoints are included in `contracts/openapi.yaml`; Better Auth handles their execution and remaining session endpoints.

### Email code

1. Send `POST /api/auth/email-otp/send-verification-otp` with `{"email":"athlete@example.com","type":"sign-in"}`. Both new and existing addresses return `{"success":true}` after the email provider accepts delivery. Acceptance does not guarantee inbox placement. A delivery failure returns HTTP 503, never a fake success.
2. Show a six-digit code entry with iOS `.oneTimeCode` autofill and a numeric keyboard. Keep the code as a string to preserve leading zeros. Allow editing the email address.
3. Send `POST /api/auth/sign-in/email-otp` with `{"email":"athlete@example.com","otp":"012345"}`. Optional `name` (up to 100 characters) sets the initial account name. Do not send other profile/authentication fields.
4. Store the returned `token` in Keychain, then call `GET /v1/bootstrap` with `Authorization: Bearer TOKEN` and continue onboarding or restore. The response also includes `user` (`id`, `email`, `emailVerified`, `name`, nullable `image`, `createdAt`, `updatedAt`). Never log tokens or codes.

Emails are normalized to lowercase. Codes expire after ten minutes, work once, and permit five incorrect attempts before a new code is required. Resending rotates the code; only the newest code is usable. Send requests have a 60-second cooldown and a maximum of three per address in an hour. The server enforces these limits in PostgreSQL across instances/restarts, including failed delivery attempts. HTTP 429 includes `Retry-After` seconds; use this for the countdown instead of assuming it is always 60. For delivery HTTP 503, show the failure and respect `Retry-After` before a new request. Invalid/expired/replayed codes return 400; exhausted attempts can return 403. Do not automatically resend in a loop.

Codes are stored as HMACs keyed by the server secret, compared in constant time, and consumed atomically. A blocked resend preserves the pending code. Resend delivery retries use one idempotency key; delivery failures remove the unusable challenge. The OTP plugin uses the existing verification table; migration `0004` adds persistent send limits and unique identity/challenge constraints. Duplicate historical ephemeral challenges are reduced to their newest row during migration; users and sessions are preserved.

### Google and Apple

Use the native provider SDK to obtain a signed **ID token**, then call:

```json
POST /api/auth/sign-in/social
{
  "provider": "google",
  "idToken": {
    "token": "PROVIDER_ID_TOKEN",
    "nonce": "ORIGINAL_RANDOM_NONCE"
  }
}
```

Use `"apple"` for Apple. Generate a cryptographically random nonce of 16–256 characters for each interactive attempt. Supply it through Google's SDK overload supporting `nonce`. Configure `GIDServerClientID` to the server's Google web client ID; the separately configured iOS audience is also accepted. For Apple, set the authorization request nonce to SHA256(original nonce), and send the original to this API. Apple tokens using an exact nonce are also supported. The server verifies signatures through provider JWKS, issuer, configured audience, token age/expiry and nonce. Missing nonce, an access token in place of an ID token, or a mismatched nonce is rejected. See Google's [SDK nonce API](https://github.com/google/GoogleSignIn-iOS/blob/main/GoogleSignIn/Sources/Public/GoogleSignIn/GIDSignIn.h) and [backend integration](https://developers.google.com/identity/sign-in/ios/backend-auth).

Request Apple `email` and `fullName` scopes on first authorization. When available, send the name as `idToken.user.name: {"firstName":"...","lastName":"..."}` (omit absent components); persist it locally as Apple may supply it once. A later Apple token without email can sign in only when its verified Apple subject already has an account binding. An unknown subject without email is rejected; the backend never invents an email or trusts a client-supplied email. Private relay emails are accepted. Production email delivery to Apple's relay also requires your sending domain/address to be registered with Apple.

Successful native exchange returns `{"redirect":false,"token":"...","user":{...}}`; store/use the session exactly as with email OTP. Verified matching emails link to one account only when the existing local email is also verified. An unverified provider email is rejected. Different emails, including an Apple relay address versus a personal Gmail address, are separate accounts; there is no implicit merge by name. An existing provider binding remains attached to its original account even if its email changes.

Browser OAuth is also supported by Better Auth on `/api/auth/sign-in/social` with `provider` and a trusted `callbackURL`, without `idToken`. Its state/PKCE/callback protections remain enabled; the OpenAPI request describes the native app flow. Native Google/Apple sessions in tests use cryptographically signed fixture tokens with mocked public-key endpoints, without real provider accounts.

### Sessions and errors

`GET /api/auth/get-session` checks the bearer session; `POST /api/auth/sign-out` with that bearer token revokes it. Remove it from Keychain after logout. Sessions use Better Auth's seven-day default expiry and refresh after one day of use; clients should reauthenticate on 401. A fresh sign-in is required for sensitive operations such as account deletion. Authentication errors use Better Auth's `{code,message}` envelope, distinct from the domain API's `{error:{...}}` envelope. Always use HTTPS outside local development.

## Local Docker workflow

`make up` starts API and PostgreSQL; the migration helper exits after setup. Mailpit has been removed. Resend delivers actual OTP email in development as well as production. In the ignored `.env`, configure `AUTH_EMAIL_TRANSPORT=resend`, `RESEND_API_KEY` and `AUTH_EMAIL_FROM` on a verified domain, then run `make up` to apply the environment. Compose keeps password sign-in disabled and honors the configured email transport.

Until credentials are available, `AUTH_EMAIL_TRANSPORT=disabled` keeps the API running and advertises `emailOtp:false`; email sign-in returns an explicit unavailable error. It does not create an authentication bypass. Setting `resend` with missing credentials or a `.test` sender fails configuration validation. Existing `.env` files are preserved by setup, so replace any old `mailpit` transport value manually.

For host Bun, start `docker compose up --detach --wait postgres`, use the same Resend configuration, and follow [development.md](development.md). Automated tests inject a mailer or mock Resend HTTP and do not deliver real email. Password auth remains an opt-in isolated-test utility only, forbidden in production and disabled by standard Compose development.

## Production configuration

| Method | Required configuration |
| --- | --- |
| Google | `GOOGLE_CLIENT_ID` (web client), `GOOGLE_CLIENT_SECRET`; optional `GOOGLE_IOS_CLIENT_ID` additional native audience |
| Apple | `APPLE_CLIENT_ID` (Services ID), `APPLE_CLIENT_SECRET` (signed client-secret JWT), `APPLE_APP_BUNDLE_IDENTIFIER` (native app ID) |
| Email | `AUTH_EMAIL_TRANSPORT=resend`, `AUTH_EMAIL_FROM=signin@YOUR_VERIFIED_DOMAIN`, `RESEND_API_KEY` |

Register browser callbacks as `https://YOUR_API_HOST/api/auth/callback/google` and `/api/auth/callback/apple`. Apple browser callbacks require a registered HTTPS domain; localhost is not supported. Configure Google consent/OAuth clients and Apple's Sign in with Apple capability/grouping for the actual app. Rotate Apple's client-secret JWT before it expires (maximum six months). No credentials are bundled and these providers stay unavailable until configured. Partial provider configuration fails startup with sanitized field errors.

Resend delivery uses plain text and HTML, a branded sender, no OTP in the subject, a ten-second timeout per attempt and at most one transient retry with the same idempotency key. Verify your sending domain and publish the provider's SPF/DKIM records and your DMARC policy before live use. `disabled` leaves email sign-in explicitly unavailable. Keep production secrets in the hosting secret store. Changing `BETTER_AUTH_SECRET` invalidates outstanding OTP hashes as well as affecting signed auth material.

The initial deployment is a single API instance: Better Auth's per-IP limits are process-local; the address cooldown/quota and single-use codes are database-backed. Configure the reverse proxy to replace untrusted forwarded IP headers. Live Google/Apple sign-ins and delivery/inbox placement with the real domain still require configured credentials and device/provider acceptance testing. `make check` covers OTP registration/login/logout, replay/concurrency, expiration, attempts/quotas, failed delivery, native JWT validation and account linking. `make build` verifies the production image.

Implementation follows the pinned Better Auth provider/plugin contracts: [email OTP](https://better-auth.com/docs/plugins/email-otp), [Google](https://better-auth.com/docs/authentication/google), [Apple](https://better-auth.com/docs/authentication/apple), plus the [Resend send API](https://resend.com/docs/api-reference/emails/send-email).
