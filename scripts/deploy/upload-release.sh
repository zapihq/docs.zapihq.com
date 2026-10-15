#!/usr/bin/env bash
set -Eeuo pipefail

scp ${SSH_OPTIONS} -P "${SSH_PORT}" "${APP_NAME}-${GITHUB_SHA}.tar.gz" \
  "${SSH_USER}@${SSH_HOST}:/tmp/${APP_NAME}-${GITHUB_SHA}.tar.gz"
