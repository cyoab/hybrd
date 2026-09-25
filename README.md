# hybrd

Local-first hybrid training: a native iOS app backed by a Bun/Hono control plane and PostgreSQL. This repository contains the backend MVP and the separately developed native iPhone/Watch app under `ios/`.

The original [product requirements](hybrd_mvp_product_design_requirements.md) and [technical architecture](hybrd_technical_architecture_v0.1.md) remain at the repository root.

## Start development

Install and start Docker Desktop (or Docker Engine with Compose v2+) and use:

```sh
make up
```

This creates a private, ignored `.env` with a unique auth secret, builds the Bun development image, starts PostgreSQL, installs locked dependencies into a container volume, applies migrations, seeds a development policy, and starts the API with source watching. Host Bun/Node/PostgreSQL are not required. `make` and `openssl` are used by the setup helper.

- API: <http://localhost:3000>
- Readiness: <http://localhost:3000/health/ready>
- OpenAPI: <http://localhost:3000/openapi.json>
- PostgreSQL: `localhost:54329`, database/user `hybrd`, local password from `.env`

API and database ports bind to loopback by default. Change `API_PORT` or `POSTGRES_PORT` in `.env` if occupied. If changing the API port, update `BETTER_AUTH_URL` and `TRUSTED_ORIGINS` too. See [local development](docs/development.md) for physical-device access and host-side Bun.

The direct Compose equivalent is:

```sh
sh scripts/setup.sh
docker compose up --build --detach --wait
```

Configure `AUTH_EMAIL_TRANSPORT=resend`, `RESEND_API_KEY` and a verified `AUTH_EMAIL_FROM` in `.env` for real email sign-in, then run `make up`. Until configured, email auth stays explicitly disabled while the API runs. The only long-running development containers are API and PostgreSQL.

## Daily commands

| Command | Purpose |
| --- | --- |
| `make logs` | Follow API logs |
| `make ps` | Inspect services |
| `make down` | Stop services; keep database data |
| `make shell` / `make db-shell` | API shell / PostgreSQL console |
| `make check` | Lint, types, unit tests, contract check, isolated PostgreSQL integration tests |
| `make progress-benchmark` | Measure progress APIs with 10,000 results in the isolated test database |
| `make format` | Format and fix server code |
| `make db-generate` / `make migrate` | Generate / apply migrations |
| `make seed` | Reapply idempotent development fixtures |
| `make openapi` | Regenerate `contracts/openapi.yaml` |
| `make build` | Build the production image |

## Backend capabilities

- Google, Apple and email OTP registration/sign-in, verified account linking and bearer sessions. See the [authentication and iOS contract](docs/authentication.md); Resend delivers OTP emails in development and production.
- Athlete onboarding data, a versioned exercise/equipment catalog and remote training policy.
- Transactional sync with idempotency, revision conflicts, paging, restore and tombstones.
- Immutable run/strength plans, explicit plan activation/audit history and separate actual workout results.
- HealthKit activity provenance, matching references and duplicate detection.
- Strava connection, reviewed onboarding history (HR zones, volume, pace and observed best efforts), and automatic workout summary publishing. See the [Strava contract and setup](docs/strava-integration.md).
- Progress summaries, revocable milestones, exact run/strength comparisons and paginated activity, with transactional projections and private conditional caching. See the [progress implementation and client contract](docs/progress-metrics-implementation.md).
- Jev bounded decisions and a structured AI coach with consent, entitlements, quotas and accepted proposals.
- Verified StoreKit subscriptions/server notifications, APNs delivery and account export/deletion.
- Typed OpenAPI, real PostgreSQL/auth integration tests, provider adapter tests, CI and a production Docker image.

Run `make check` for the complete suite. Tests use injected external providers, never paid requests or real notifications. Apple/OpenRouter/APNs credentials and product identifiers are optional for local development; configured capabilities are advertised by bootstrap. See [deployment](docs/deployment.md) for live-provider validation and release setup. The iOS training engine remains responsible for training computation and candidate generation.

## Repository map

```text
ios/                         Native iPhone/Watch app and local training models
server/
  src/
    api/                     App factory, errors, schemas, service wiring
    auth/                    Better Auth and athlete provisioning
    athlete/                 Athlete profile and onboarding schemas
    sync/                    Typed mutations, replay ledger, conflicts and restore
    plans/                   Immutable prescriptions, activation and history
    workouts/                Actual results and activity provenance
    progress/                Versioned metrics, projections, cache and history
    strava/                  OAuth, history previews, durable jobs and publishing
    intelligence/jev/        Versioned bounded-decision registry
    intelligence/llm/        Server-controlled model selection
    catalog/                 Versioned exercises, muscles and equipment
    ops/                     Policy, catalog, retention and push commands
    config/                  Environment validation and development policy
    billing/                 Verified StoreKit lifecycle and entitlements
    notifications/           APNs delivery and idempotency
    db/                      Database client, schemas, migrations, fixtures
    telemetry/               Structured metadata-only logging
  migrations/                Versioned SQL and Drizzle snapshots
  openapi/                   Offline contract generation
  tests/                     Unit and PostgreSQL/auth integration tests
contracts/openapi.yaml       Generated client contract
docs/                        Development, handoff, implementation, deployment
compose.yaml                 Docker development and test services
server/Dockerfile            Development and production stages
railway.json                 Deployment configuration; nothing deployed yet
```

Start with the [iOS handoff](docs/ios-handoff.md), [implementation status](docs/implementation.md), and [deployment guide](docs/deployment.md).

The proposed next AI phase is documented in the [AI agent implementation plan](docs/ai-agent-implementation-plan.md) and [iOS harness contract review](docs/ai-ios-harness-review.md). These describe planned capabilities, not currently available endpoints.
