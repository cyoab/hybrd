# Development environment

## Docker workflow

Run `make up` from the repository root. Only two long-running development services are started: `api` and `postgres`. `migrate` runs once per Compose startup and exits successfully before the API starts. It uses a frozen Bun lockfile, applies reviewed SQL, and inserts the development policy and exercise catalog if missing.

Source is bind-mounted, so `server/src` edits restart Bun automatically. `node_modules` lives in a named Linux container volume rather than using host dependencies. The hoisted workspace layout is explicitly configured in `bunfig.toml`. PostgreSQL data lives in the project's `postgres_data` volume and survives `make down`.

`.env` is ignored; `.env.example` documents available settings. Compose overrides the host database URL with its internal `postgres:5432` address. Database credentials in the local example are for local use only. If changing credentials, keep the host `DATABASE_URL` consistent and URL-encode any special characters when constructing a URL. PostgreSQL initialization variables apply only when its data volume is first created.

## Dependencies and checks

With the API running, install dependencies in the container:

```sh
docker compose exec -w /app/server api bun add --exact PACKAGE_NAME
docker compose exec api bun add --dev --exact PACKAGE_NAME
```

Commit both package manifests and `bun.lock`. Rebuild with `make up` after dependency or Dockerfile changes. Dependency installation is serialized through the migration service at development startup.

`make check` runs the same checks as CI in the `test` container, using `postgres-test`. That database is separate, has no exposed host port, and stores data in tmpfs. Test setup refuses to use a database whose name does not end in `_test`. The test suite creates and removes its own test users and all associated domain records. `make down` also stops the test database.

With Bun 1.4.2 installed locally, fast checks need no containers:

```sh
bun install --frozen-lockfile
bun run check
```

## Migrations and policy fixtures

1. Edit the Drizzle schema under `server/src/db/schema/`.
2. Run `make db-generate` and inspect the generated SQL and snapshot.
3. Run `make migrate`, then `make check`.
4. Commit schema, migration, and metadata together. Do not rewrite applied migrations or use `drizzle-kit push` for shared databases.

Migrations also run as the Railway pre-deploy command; production startup itself never changes schema. `make seed` is development/test only and never creates default users or training records. The version 2 fixture enables implemented features and supplies example policy thresholds. External features still require configured providers, consent and entitlements. These example thresholds require product review before production. Publish an immutable production policy through `bun run ops publish-policy /path/to/policy.json`.

## Native Bun with PostgreSQL in Docker

To run the API on the host for debugging, stop any containerized API first, then:

```sh
make setup
docker compose up --detach --wait postgres
bun install --frozen-lockfile
bun --env-file=.env run db:migrate
bun --env-file=.env run db:seed
bun --env-file=.env run dev
```

The host process reads `DATABASE_URL` from `.env`. If `POSTGRES_PORT` changes, update that URL too. `API_PORT` controls Docker's published port; host Bun reads `PORT` instead.

## iOS Simulator and physical iPhone

The simulator can use `http://localhost:3000`. The iOS agent owns development-only App Transport Security settings and endpoint selection.

A physical phone cannot reach the Mac through its own `localhost`. For device testing, create an ignored `compose.override.yaml` that replaces the API port binding:

```yaml
services:
  api:
    ports: !override
      - "0.0.0.0:3000:3000"
```

Use Compose 2.24.4+ for `!override`, set `BETTER_AUTH_URL` and `TRUSTED_ORIGINS` to the Mac's reachable development origin, restart Compose, and use that origin on the phone. Keep PostgreSQL on loopback. Restore the loopback API binding after testing. Apple browser OAuth callbacks require a registered HTTPS domain; native ID-token exchange and local email/password sessions are described in the handoff.

## Troubleshooting

- Docker socket/daemon errors: start Docker Desktop, then run `docker info`.
- Port already allocated: change the relevant port variables and matching URLs in `.env`.
- API waiting for migrations: inspect `docker compose logs migrate postgres`.
- Dependencies out of sync: run `make up`; installation validates `bun.lock` before starting the API.
- Missing policy: run `make seed` in development.
- Stale API contract: run `make openapi` and inspect the diff.

`make down` preserves data. `docker compose --profile test down --volumes` also deletes the development database and dependency volumes; use it only when you deliberately want to discard local data.

## Test cloud intelligence locally

Set your OpenRouter key/model in the ignored `.env`, restart with `make up`, and grant an explicitly chosen test athlete seven days of access:

```sh
docker compose exec api bun run ops grant-dev-entitlement ATHLETE_UUID pro
```

This command refuses production. Update the athlete profile consent through sync before making requests. The automated tests use injected providers and incur no provider charges. StoreKit/APNs require real app identifiers and keys for live sandbox tests; absent configuration is reported in bootstrap capabilities and returns explicit unavailable errors.
