#!/usr/bin/env bash
# The health contract: GET /api/health answers 200 with {"status":"ok"}.
#
# Three call sites speak it:
#   - scripts/check-container.sh  container seam check (60 attempts)
#   - scripts/deploy/remote.sh    deploy verification (30 attempts)
#   - Dockerfile HEALTHCHECK      image-level probe (cannot source this file)
#
# The Dockerfile probe runs in the runtime layer, which carries only the
# standalone server and no repository scripts, so it stays a standalone node
# one-liner that must be kept in sync by hand. app/api/health/route.ts is the
# endpoint itself.
#
# This file is sourced, not executed, and must not set shell options.

HEALTH_PATH="/api/health"
HEALTH_BODY='{"status":"ok"}'

health_url() {
  printf 'http://127.0.0.1:%s%s' "$1" "$HEALTH_PATH"
}

# wait_for_health <port> <attempts>
# Prints the last body it saw and returns 0 only when that body matched. The
# probe is quiet: a retry loop must not fill the log with curl's connection
# errors while the application is still starting.
wait_for_health() {
  local port="$1"
  local attempts="$2"
  local body=""
  local _

  for _ in $(seq 1 "$attempts"); do
    body="$(curl --silent --max-time 5 "$(health_url "$port")" 2>/dev/null || true)"
    if [ "$body" = "$HEALTH_BODY" ]; then
      printf '%s' "$body"
      return 0
    fi
    sleep 1
  done

  printf '%s' "$body"
  return 1
}
