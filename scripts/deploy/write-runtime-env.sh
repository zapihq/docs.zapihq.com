#!/usr/bin/env bash
set -Eeuo pipefail

trim() {
  printf '%s' "$1" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

SSH_PORT="$(trim "${SSH_PORT:-}")"
SSH_USER="$(trim "${SSH_USER:-}")"
SSH_HOST="$(trim "${SSH_HOST:-}")"
DEPLOY_PATH="$(trim "${DEPLOY_PATH:-}")"
PORT="$(trim "${PORT:-}")"

RUNTIME_ENV_BODY="$(printf '%s\n' "${RUNTIME_ENV_FILE:-}" | sed '/^PORT=/d')"

ssh ${SSH_OPTIONS} -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" "install -m 755 -d '${DEPLOY_PATH}/shared'"
{
  if [ -n "${RUNTIME_ENV_BODY}" ]; then
    printf '%s\n' "${RUNTIME_ENV_BODY}"
  fi
  if [ -n "${PORT}" ]; then
    printf 'PORT=%s\n' "${PORT}"
  fi
} | \
  ssh ${SSH_OPTIONS} -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" \
  "cat > '${DEPLOY_PATH}/shared/.env.production'"
ssh ${SSH_OPTIONS} -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" "chmod 600 '${DEPLOY_PATH}/shared/.env.production'"
