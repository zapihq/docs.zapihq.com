#!/usr/bin/env bash
# Validate the deploy job's configuration before any SSH, SCP, or registry
# call. PORT is defaulted by the workflow before this runs, so an empty PORT
# here is a real configuration error.
set -euo pipefail

for name in \
  IMAGE_TAG \
  IMAGE_REPOSITORY \
  DEPLOY_PATH \
  SSH_HOST \
  SSH_PORT \
  SSH_USER \
  PORT \
  SSH_PRIVATE_KEY \
  SSH_KNOWN_HOSTS; do
  if [ -z "${!name:-}" ]; then
    printf '::error::Missing deploy configuration: %s\n' "$name"
    exit 1
  fi
done

printf 'Deploying %s:%s to %s\n' "$IMAGE_REPOSITORY" "$IMAGE_TAG" "$DEPLOY_PATH"
