#!/usr/bin/env bash
# Resolve the image this deploy will run and publish the image group once.
#
# Inputs, both optional:
#   REQUESTED_TAG  the workflow_dispatch input; a dispatch carrying a tag is a
#                  rollback and always deploys that tag
#   BUILT_TAG      the immutable tag this run's publish produced
#
# Outputs to $GITHUB_ENV, so every later step reads one group:
#   IMAGE_TAG, IMAGE_REPOSITORY, IMAGE_SOURCE
#
# Fails when neither input names a tag, or when the tag is not valid Docker tag
# grammar. Besides rejecting typos, the grammar is what makes the tag safe to
# carry into the remote shell and compose interpolation.
set -euo pipefail

if [ -n "${REQUESTED_TAG:-}" ]; then
  tag="$REQUESTED_TAG"
  echo "Deploy mode: rollback to an earlier published tag"
elif [ -n "${BUILT_TAG:-}" ]; then
  tag="$BUILT_TAG"
  echo "Deploy mode: this run's build"
else
  echo "::error::No image tag: pass image_tag, or deploy a commit that publishes one."
  exit 1
fi

if ! [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$ ]]; then
  echo "::error::Invalid image_tag '${tag}': expected a Docker tag such as sha-1a2b3c4."
  exit 1
fi

# GHCR requires a lowercase repository name.
repository="ghcr.io/${GITHUB_REPOSITORY,,}"
{
  echo "IMAGE_TAG=${tag}"
  echo "IMAGE_REPOSITORY=${repository}"
  echo "IMAGE_SOURCE=${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
} >> "$GITHUB_ENV"
echo "::notice title=Deploy target::${repository}:${tag}"
