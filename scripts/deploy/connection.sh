#!/usr/bin/env bash
# The single SSH/SCP seam for the deploy path.
#
# Usage:
#   connection.sh run "<remote command>"      # stdin is streamed to the remote
#   connection.sh copy <local-path> <remote-path>
#
# The connection group lives here, once: SSH_HOST, SSH_PORT, SSH_USER,
# SSH_OPTIONS, and the deploy key at ~/.ssh/id_ed25519. Callers never repeat
# host, user, port, key, or options flags. SSH_OPTIONS is the one shared value
# for both commands; its default is the deploy's hardened option set, and an
# already-exported value wins. The only connection flag that differs between
# ssh and scp is the port (-p vs -P), and that difference lives here too.
#
# Missing SSH_HOST, SSH_PORT, or SSH_USER is a configuration error: exit 2
# before ssh or scp runs, so a caller cannot mistake it for a remote failure.
set -euo pipefail

SSH_KEY="${HOME}/.ssh/id_ed25519"
SSH_OPTIONS="${SSH_OPTIONS:--o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${HOME}/.ssh/known_hosts}"

usage() {
  printf 'usage: connection.sh run "<remote command>" | connection.sh copy <local-path> <remote-path>\n' >&2
  exit 64
}

require_settings() {
  local name
  for name in SSH_HOST SSH_PORT SSH_USER; do
    if [ -z "${!name:-}" ]; then
      printf '::error::Missing SSH configuration: %s\n' "$name" >&2
      exit 2
    fi
  done
}

case "${1:-}" in
  run)
    [ "$#" -eq 2 ] || usage
    require_settings
    target="${SSH_USER}@${SSH_HOST}"
    # shellcheck disable=SC2086 # SSH_OPTIONS is a space-separated option list
    exec ssh -i "$SSH_KEY" ${SSH_OPTIONS} -p "$SSH_PORT" "$target" "$2"
    ;;
  copy)
    [ "$#" -eq 3 ] || usage
    require_settings
    target="${SSH_USER}@${SSH_HOST}"
    # shellcheck disable=SC2086 # SSH_OPTIONS is a space-separated option list
    exec scp -i "$SSH_KEY" ${SSH_OPTIONS} -P "$SSH_PORT" "$2" "${target}:$3"
    ;;
  *)
    usage
    ;;
esac
