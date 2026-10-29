#!/usr/bin/env bash
# Exercise the built image from the outside: boot it, wait for the health
# contract, and check the container seam — health, the image healthcheck,
# the non-root user, a rendered docs page, the docs index, and a 404.
# Run locally with `bash scripts/check-container.sh <image> [port]`.
set -euo pipefail

IMAGE="${1:?usage: check-container.sh <image> [port]}"
PORT="${2:-3000}"
CONTAINER="zapi-docs-check-$$"
BASE_URL="http://127.0.0.1:${PORT}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
  docker rm --force "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  docker logs "$CONTAINER" 1>&2 2>/dev/null || true
  exit 1
}

docker run --detach --name "$CONTAINER" \
  --publish "127.0.0.1:${PORT}:3000" \
  "$IMAGE" >/dev/null

# 1. Health returns 200 with the documented body.
body=""
for _ in $(seq 1 60); do
  body="$(curl --silent --max-time 5 "${BASE_URL}/api/health" 2>/dev/null || true)"
  if [ "$body" = '{"status":"ok"}' ]; then
    break
  fi
  sleep 1
done
if [ "$body" != '{"status":"ok"}' ]; then
  fail "GET /api/health returned '${body}', expected '{\"status\":\"ok\"}'"
fi

# 2. The image's own healthcheck reaches healthy.
health=""
for _ in $(seq 1 45); do
  health="$(docker inspect \
    --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' \
    "$CONTAINER")"
  if [ "$health" = "healthy" ]; then
    break
  fi
  if [ "$health" = "unhealthy" ]; then
    fail "image healthcheck reported unhealthy"
  fi
  sleep 2
done
if [ "$health" != "healthy" ]; then
  fail "image healthcheck status was '${health}', expected 'healthy'"
fi

# 3. The container runs as non-root.
uid="$(docker exec "$CONTAINER" id -u)"
if [ "$uid" = "0" ]; then
  fail "container runs as root, expected the non-root node user"
fi

# 4. A real documentation page returns 200 with rendered MDX.
page="$TMP_DIR/page.html"
status="$(curl --silent --max-time 10 \
  --output "$page" --write-out '%{http_code}' "${BASE_URL}/docs/quickstart")"
if [ "$status" != "200" ]; then
  fail "GET /docs/quickstart returned ${status}, expected 200"
fi
if ! grep --quiet 'Get a test key' "$page"; then
  fail "GET /docs/quickstart did not contain rendered documentation content"
fi

# 5. The machine-readable docs index returns 200.
status="$(curl --silent --max-time 10 \
  --output /dev/null --write-out '%{http_code}' "${BASE_URL}/llms.txt")"
if [ "$status" != "200" ]; then
  fail "GET /llms.txt returned ${status}, expected 200"
fi

# 6. An unknown path still returns 404.
status="$(curl --silent --max-time 10 \
  --output /dev/null --write-out '%{http_code}' "${BASE_URL}/this-page-does-not-exist")"
if [ "$status" != "404" ]; then
  fail "GET /this-page-does-not-exist returned ${status}, expected 404"
fi

printf 'Container checks passed for %s (uid %s, healthcheck healthy).\n' "$IMAGE" "$uid"
