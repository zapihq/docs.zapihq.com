# syntax=docker/dockerfile:1

# Reproducible image for the docs site. The build context is the repository
# root; .dockerignore keeps dependencies, build output, git history,
# worktrees, and env files out of it while keeping content/ (MDX is a build
# input).

FROM node:22-bookworm-slim AS base
RUN npm install --global pnpm@11.17.0
ENV NEXT_TELEMETRY_DISABLED=1

FROM base AS deps
WORKDIR /app

# Install from the lockfile before copying the app, so a content-only change
# does not bust the dependency layer. The root postinstall generates the
# fumadocs .source tree, which needs the source config and content, so skip it
# here and generate it explicitly in the builder.
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile --ignore-scripts

FROM base AS builder
WORKDIR /app

# The fumadocs last-modified plugin always shells out to git. The build
# context excludes .git, so git is here only so it can report "no history"
# instead of the build failing with ENOENT.
RUN apt-get update && \
    apt-get install --yes --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

# The public site URL is rendered into the output, so it is a build argument
# rather than a runtime variable.
ARG NEXT_PUBLIC_SITE_URL=""
ENV NEXT_PUBLIC_SITE_URL=${NEXT_PUBLIC_SITE_URL}
RUN test -n "${NEXT_PUBLIC_SITE_URL}" || \
    { echo "NEXT_PUBLIC_SITE_URL is required as a build argument" >&2; exit 1; }

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN pnpm exec fumadocs-mdx
RUN pnpm build

FROM node:22-bookworm-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
ENV NEXT_TELEMETRY_DISABLED=1

# The runtime layer carries the standalone server, the static assets it
# expects beside it, and public files. Nothing else.
COPY --from=builder --chown=node:node /app/.next/standalone ./
COPY --from=builder --chown=node:node /app/.next/static ./.next/static
COPY --from=builder --chown=node:node /app/public ./public

USER node
EXPOSE 3000

# Health contract: 200 with {"status":"ok"}. Keep this in sync with
# app/api/health/route.ts; it is intentionally dependency-free so it cannot
# fail on an upstream call.
HEALTHCHECK --interval=10s --timeout=5s --start-period=20s --retries=5 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.PORT || 3000) + '/api/health').then(async (res) => { const body = await res.json().catch(() => null); process.exit(res.status === 200 && body && body.status === 'ok' ? 0 : 1); }).catch(() => process.exit(1));"]

CMD ["node", "server.js"]
