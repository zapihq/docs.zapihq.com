#!/usr/bin/env bash
set -Eeuo pipefail

test -n "${SSH_PORT}" || { echo "Missing Actions variable: SSH_PORT"; exit 1; }
test -n "${SSH_USER}" || { echo "Missing Actions variable: SSH_USER"; exit 1; }
test -n "${SSH_HOST}" || { echo "Missing Actions variable: SSH_HOST"; exit 1; }
test -n "${DEPLOY_PATH}" || { echo "Missing Actions variable: DEPLOY_PATH"; exit 1; }
test -n "${SERVICE_NAME}" || { echo "Missing Actions variable: SERVICE_NAME"; exit 1; }
