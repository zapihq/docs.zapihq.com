#!/usr/bin/env bash
#set -Eeuo pipefail

#scp ${SSH_OPTIONS} -P "${SSH_PORT}" "${APP_NAME}-${GITHUB_SHA}.tar.gz" \
#  "${SSH_USER}@${SSH_HOST}:/tmp/${APP_NAME}-${GITHUB_SHA}.tar.gz"

#!/usr/bin/env bash
set -Eeuo pipefail

# Automatically add the server's host key to known_hosts to satisfy strict checking
mkdir -p ~/.ssh
ssh-keyscan -H "${SSH_HOST}" >> ~/.ssh/known_hosts 2>/dev/null || true
chmod 600 ~/.ssh/known_hosts

scp ${SSH_OPTIONS} -P "${SSH_PORT}" "${APP_NAME}-${GITHUB_SHA}.tar.gz" \
  "${SSH_USER}@${SSH_HOST}:/tmp/${APP_NAME}-${GITHUB_SHA}.tar.gz"
