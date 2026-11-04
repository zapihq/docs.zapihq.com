#!/usr/bin/env bash
# Remove the staged registry token from the deploy host.
#
# The workflow stages the run's short-lived GITHUB_TOKEN at
# ${DEPLOY_PATH}/.ghcr-token before the remote deploy program logs in. The
# remote program removes it in its own exit trap; this script is the
# out-of-band path for a cancelled or failed run. It is best-effort: it warns
# and exits 0 so cleanup can never replace the deploy's real conclusion.
#
# This path intentionally does not log out: the remote program's
# `trap logout EXIT` owns the registry session, and this path only removes the
# staged file.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for name in DEPLOY_PATH SSH_HOST SSH_PORT SSH_USER; do
  if [ -z "${!name:-}" ]; then
    printf '::warning::Skipping staged registry token cleanup: missing %s\n' "$name" >&2
    exit 0
  fi
done

if [ ! -f ~/.ssh/id_ed25519 ]; then
  printf '::warning::Skipping staged registry token cleanup: the deploy key was never prepared\n' >&2
  exit 0
fi

token_path="${DEPLOY_PATH}/.ghcr-token"
quoted_path="$(printf '%q' "$token_path")"

if bash "$script_dir/connection.sh" run "rm -f -- $quoted_path"; then
  exit 0
fi

printf '::warning::Could not remove the staged registry token from %s@%s:%s\n' \
  "$SSH_USER" "$SSH_HOST" "$token_path" >&2
exit 0
