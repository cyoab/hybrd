# Athlete profile integrations

## Implemented locally

`AthleteProfileEditor` holds an editable draft. `TrainingStore.saveProfile(_:replacing:)` validates it, checks that the stored profile still matches the editor's original, and persists only the profile. Existing plan snapshots, actual results, and workout drafts remain unchanged. A new starter block has a separate review and acceptance flow.

`HealthProfileReader` requests read-only HealthKit access to date of birth, body mass, and height after the athlete taps Import. The latest available weight and height include sample dates in `HealthImportReviewView`. Missing results do not imply denial: Health may have no value or the athlete may not have shared it. Existing entries are unselected by default. Applying an import changes the editor; Save profile commits it. Measurements use kilograms and centimeters. There is no background import, Health writing, zone import, or PR inference.

The iPhone target includes the HealthKit entitlement and `NSHealthShareUsageDescription`. App identifier assignment was attempted through Bitrig but returned `not_configured` because no Apple account is connected. Connect the account in Bitrig Project Settings → Distribute, assign the app identifier through Bitrig, and verify provisioning and the permission/review flow on a physical iPhone using Run on…. Device authorization is not yet verified.

Personal BPM boundaries are entered explicitly. Strength records can be manually entered or reviewed from completed local sets; the latter retain logged provenance. Neither experience nor records currently compute prescribed loads.

## Strava: deferred by product decision

No developer app or OAuth backend is configured. The profile therefore shows Coming soon and keeps all editors usable independently. No credentials, fake connection state, or unusable authorization button are bundled.

Before implementing live import:

1. Register the Strava app, decide its callback domain, and configure its client ID and server-held secret. Implement authenticated linking, connection status, import preview, and disconnect operations in the backend contract before generating the native client from `../contracts/openapi.yaml`.
2. Start consent from the app with a server-bound, expiring state value. Validate callback identity and state, exchange the single-use code on the server, and persist granted scopes and rotating tokens securely. Keep provider secrets and refresh tokens off the iPhone; keep the hybrd session credential in Keychain.
3. Request only read scopes needed by the selected import. Honor partial consent and distinguish cancellation, expired authorization, rate limiting, and no available data. For mobile authorization, follow Strava's documented app flow with an `ASWebAuthenticationSession` fallback. Add callback/query schemes only when their real values are configured.
4. Return normalized candidate values to an explicit review screen. Preserve manual entries unless the athlete chooses replacements. Disconnect must stop subsequent imports; deleting a provider connection must not silently erase performed workout history.
5. Verify denied and partial consent, callback replay rejection, refresh rotation, revocation, pagination, duplicate imports, and unit conversions against a development account.

Provider mechanics and scope names must follow the current [Strava authentication guide](https://developers.strava.com/docs/authentication/). These are planned integration requirements, not implemented endpoints.

## Candidate data mapping

| Candidate | Local destination | Required treatment |
| --- | --- | --- |
| Available profile weight | `AthleteDetails.weightKilograms` | Confirm units and provenance; review before replacing. |
| Available personal HR ranges | `PersonalHeartRateZones` | Check endpoint access, range count, boundary conventions, and strict ordering. Do not infer from age. |
| Running best efforts | `RunningPersonalBest` | Preserve distance, elapsed time, source activity ID, and history coverage. An activity-specific best effort is not automatically an all-time PR. |
| Height, birth date, lifting records | Existing manual/Health fields | Do not assume Strava supplies these or fabricate missing values. |

Validate available fields and account access against the [Strava API reference](https://developers.strava.com/docs/reference/) when implementing. Provider IDs, measurement timestamps, imported-record provenance, and sync metadata will require explicit contract/model additions; `lastHealthImport` alone is not a general import ledger.

## Exercise catalog boundary

The app bundles 876 text records from [Free Exercise DB](https://github.com/yuhonas/free-exercise-db), pinned to `a859101d633a01c4a1a920d6a8ce41dabba0705f`, with its Unlicense and source note under `App/Resources/ExerciseCatalog/`. No source images are bundled.

The public library's string IDs and broad equipment categories are reference data. They must not be submitted as the backend catalog's canonical UUIDs or treated as complete equipment requirements. The reviewed local starter recipes maintain their own explicit equipment sets. Any future backend exercise mapping must be versioned and preserve existing prescriptions.

## Verification status

Bitrig builds and the core executable checks pass. An isolated in-memory SwiftData harness exercised the actual profile-save implementation, including save/reload, stale edits, invalid edits, and preservation of plans/results/drafts. Temporary offscreen macOS SwiftUI renders covered profile layouts. Interactive iPhone accessibility, real Health authorization, Strava, and paired Watch delivery remain unverified; simulator inspection is unavailable in the current Bitrig destination.
