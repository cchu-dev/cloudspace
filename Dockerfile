# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim AS deps

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    g++ \
    git \
    make \
    python3 \
  && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci --include=optional

FROM deps AS build

COPY tsconfig.json tsconfig.build.json vite.config.ts ./
COPY scripts ./scripts
COPY src ./src

RUN npm run build
RUN npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production \
  HOST=0.0.0.0 \
  PORT=3000 \
  DEVSPACE_CONFIG_DIR=/data/config \
  DEVSPACE_STATE_DIR=/data/state \
  DEVSPACE_WORKTREE_ROOT=/data/worktrees \
  DEVSPACE_ALLOWED_ROOTS=/workspace \
  DEVSPACE_PUBLIC_BASE_URL=http://localhost:3000

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    git \
    openssh-client \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /data/config /data/state /data/worktrees /workspace \
  && chown -R node:node /app /data /workspace

COPY --from=build --chown=node:node /app/package.json /app/package-lock.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist

USER node

EXPOSE 3000

VOLUME ["/data", "/workspace"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/healthz').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "dist/cli.js", "serve"]
