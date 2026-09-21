# syntax=docker/dockerfile:1
ARG BUN_VERSION=1.4.2
FROM oven/bun:${BUN_VERSION}-debian AS base
WORKDIR /app

FROM base AS dependencies
COPY package.json bun.lock bunfig.toml ./
COPY server/package.json ./server/package.json
RUN bun install --frozen-lockfile

FROM dependencies AS development
COPY . .
ENV NODE_ENV=development
EXPOSE 3000
CMD ["bun", "run", "dev"]

FROM base AS production-dependencies
COPY package.json bun.lock bunfig.toml ./
COPY server/package.json ./server/package.json
RUN bun install --frozen-lockfile --production

FROM base AS production
ENV NODE_ENV=production
COPY --from=production-dependencies --chown=bun:bun /app/node_modules ./node_modules
COPY --chown=bun:bun package.json bunfig.toml ./
COPY --chown=bun:bun server/package.json ./server/package.json
COPY --chown=bun:bun server/src ./server/src
COPY --chown=bun:bun server/migrations ./server/migrations
COPY --chown=bun:bun server/certificates ./server/certificates
USER bun
EXPOSE 3000
CMD ["bun", "run", "start"]
