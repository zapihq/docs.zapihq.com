#!/usr/bin/env bash
# Validate the deploy job's configuration before any SSH, SCP, or registry
# call. The workflow defaults PORT to 3002 before this runs, so PORT is not
# part of the required set.
set -euo pipefail

for name in \
  IMAGE_TAG \
  IMAGE_REPOSITORY \
  DEPLOY_PATH \
  SSH_HOST \
  SSH_PORT \
  SSH_USER \
  SSH_PRIVATE_KEY \
  SSH_KNOWN_HOSTS; do
  if [ -z "${!name:-}" ]; then
    printf '::error::Missing deploy configuration: %s\n' "$name"
    exit 1
  fi
done

printf 'Deploying %s:%s to %s\n' "$IMAGE_REPOSITORY" "$IMAGE_TAG" "$DEPLOY_PATH"
