# Deployment foundation

Nothing has been provisioned or deployed. `railway.json` and the production Docker stage prepare the intended two-service topology: this API plus Railway PostgreSQL.

## Production image

```sh
make build
```

The default final stage installs only production dependencies, excludes local secrets and iOS files, runs as the `bun` user, and respects the `PORT` environment variable. Shutdown drains requests and closes the database pool. The image includes migrations so a release job can execute `bun run db:migrate` without Drizzle Kit.

## Railway setup

1. Connect the repository with its root as the build context; use `server/Dockerfile` and `railway.json`.
2. Add Railway PostgreSQL and reference its private `DATABASE_URL` in the API service.
3. Set `NODE_ENV=production`, a unique `BETTER_AUTH_SECRET` of at least 32 characters, `BETTER_AUTH_URL` to the HTTPS API origin, and exact trusted origins where applicable. Leave `DEV_AUTH_ENABLED=false`.
4. Supply the real Apple identifiers and signed client-secret JWT. Rotate the JWT before Apple's expiry limit. Keep all Apple server credentials outside the app.
5. Railway runs the checked-in migrations before deployment and probes `/health/ready`. Development seeds do not run in production. Publish reviewed policy through a future controlled workflow.

Optional OpenRouter values are reserved configuration only. AI, billing, and APNs remain unavailable until their server implementations are complete.

Run a single API instance initially. Better Auth's in-memory rate limiter is per-process; revisit that before horizontal scaling. The application uses a bounded PostgreSQL connection pool. The deployment is not publicly launch-ready: synchronization, the training domain, account deletion policy, StoreKit verification, provider validation, operational monitoring, and backup/restore procedures still need implementation and verification.

The production image deliberately does not auto-migrate on process startup. Release migrations must be serialized; do not run multiple migration jobs concurrently.
