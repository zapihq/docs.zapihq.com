#!/usr/bin/env bash
# Prepare the deploy credentials for the connection seam.
#
# Owns the credential group: SSH_PRIVATE_KEY and SSH_KNOWN_HOSTS arrive as raw
# secret values from the workflow environment. This script writes them where
# connection.sh expects them (~/.ssh/id_ed25519 and ~/.ssh/known_hosts) with the
# modes ssh requires; it never prints either value.
set -euo pipefail

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
printf '%s\n' "$SSH_PRIVATE_KEY" > "$HOME/.ssh/id_ed25519"
chmod 600 "$HOME/.ssh/id_ed25519"
printf '%s\n' "$SSH_KNOWN_HOSTS" > "$HOME/.ssh/known_hosts"
chmod 644 "$HOME/.ssh/known_hosts"
