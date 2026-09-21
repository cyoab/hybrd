# hybrd

Local-first hybrid training: a native iOS app backed by a Bun/Hono control plane and PostgreSQL. This repository contains the non-iOS project scaffold. `ios/` is reserved for the separate iOS implementation.

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

## Daily commands

| Command | Purpose |
| --- | --- |
| `make logs` | Follow API logs |
| `make ps` | Inspect services |
| `make down` | Stop services; keep database data |
| `make shell` / `make db-shell` | API shell / PostgreSQL console |
| `make check` | Lint, types, unit tests, contract check, isolated PostgreSQL integration tests |
| `make format` | Format and fix server code |
| `make db-generate` / `make migrate` | Generate / apply migrations |
| `make seed` | Reapply idempotent development fixtures |
| `make openapi` | Regenerate `contracts/openapi.yaml` |
| `make build` | Build the production image |

## What is ready

- Bun workspace with pinned dependencies, lockfile, strict TypeScript, Biome, and Bun tests.
- Hono API with request validation, standardized errors, request IDs, bounded bodies, CORS, and privacy-conscious logging.
- Better Auth with bearer sessions, optional Apple provider configuration, and local-only email/password sign-in.
- PostgreSQL/Drizzle foundation schema and checked-in migration: authentication, athletes, policy versions, devices, entitlements, and sync bookkeeping.
- Working bootstrap, policy/ETag, device registration/revocation, entitlement reads, and health endpoints.
- Generated OpenAPI 3.1 contract shared with the iOS implementation.
- Development Compose stack, disposable test database, non-root production image, Railway configuration, and GitHub Actions checks.

## What remains scaffolded

This is the foundation, not a complete MVP. Sync handlers, the relational training domain, plan/workout persistence, exercise catalog, remote AI, StoreKit verification, APNs delivery, and account deletion remain to be implemented. Reserved HTTP routes return `501 NOT_IMPLEMENTED` and perform no work. Bootstrap advertises `sync.available: false`; the development policy disables unfinished features.

Directories for every backend module in the architecture are in place, with implementation boundaries documented. No worker, Redis, object storage, web app, or server-side training engine has been added.

## Repository map

```text
ios/                         Reserved for the iOS agent
server/
  src/
    api/                     App factory, errors, schemas, service wiring
    auth/                    Better Auth and athlete provisioning
    athlete/                 Authenticated athlete lookup
    sync/                    Draft envelopes, placeholder routes, ledger design
    plans/                   Plan/prescription implementation boundary
    workouts/                Catalog/result/provenance implementation boundary
    intelligence/jev/        Versioned bounded-decision registry
    intelligence/llm/        Server-controlled model selection
    config/                  Environment validation and development policy
    billing/                 StoreKit placeholder and entitlement boundary
    notifications/           APNs implementation boundary
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
