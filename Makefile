.DEFAULT_GOAL := help

.PHONY: help setup up down logs ps shell db-shell migrate seed db-generate openapi check test progress-benchmark format build

help:
	@echo "setup        Create .env without overwriting existing values"
	@echo "up           Start PostgreSQL, the API with hot reload, and the OTP inbox"
	@echo "down         Stop services (preserves database volume)"
	@echo "logs / ps    View API logs / service status"
	@echo "shell        Open a shell in the API container"
	@echo "db-shell     Open psql against the development database"
	@echo "migrate      Apply checked-in database migrations"
	@echo "seed         Seed idempotent development fixtures"
	@echo "db-generate  Generate a migration from Drizzle schemas"
	@echo "openapi      Regenerate the shared API contract"
	@echo "check / test Lint, typecheck, contract check, unit and isolated DB tests"
	@echo "progress-benchmark Measure progress APIs with 10,000 isolated test results"
	@echo "format       Format and fix server code with Biome"
	@echo "build        Build the production Docker image"

setup:
	@sh scripts/setup.sh

up: setup
	docker compose up --build --detach --wait

down:
	docker compose --profile test down --remove-orphans

logs:
	docker compose logs --follow api

ps:
	docker compose ps --all

shell:
	docker compose exec api sh

db-shell:
	docker compose exec postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

migrate:
	docker compose exec api bun run db:migrate

seed:
	docker compose exec api bun run db:seed

db-generate:
	docker compose exec api bun run db:generate

openapi:
	docker compose exec api bun run openapi:generate

check test: setup
	docker compose --profile test run --build --rm test

progress-benchmark: setup
	docker compose --profile test run --build --rm -e PROGRESS_BENCH_REPORT=/app/docs/progress-metrics-benchmark.json test sh -c 'bun install --frozen-lockfile && bun run db:migrate && bun run db:seed && cd server && bun test tests/bench/progress.bench.test.ts'

format:
	docker compose exec api bun run format

build:
	docker build --target production --file server/Dockerfile --tag hybrd-api:local .
