#!/usr/bin/env bash
# The registry-error vocabulary shared by the deploy and the publish check.
#
# classify_registry_error <text> prints exactly one class:
#   auth     the registry rejected the credential, or will not reveal the tag
#   missing  the tag does not exist in the repository
#   other    anything else
#
# GHCR answers "denied" both for a tag that is missing from a private package
# and for a token that cannot read it, so auth must not claim which of the two
# it was. Publish uses this to accept only auth as the anonymous-pull outcome;
# the deploy uses it to choose the pull-failure message.
#
# This file is sourced, not executed, and must not set shell options.

classify_registry_error() {
  local text
  text="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"

  case "$text" in
    *unauthorized* | *denied* | *forbidden*)
      printf 'auth'
      ;;
    *"manifest unknown"* | *"not found"* | *"no such"*)
      printf 'missing'
      ;;
    *)
      printf 'other'
      ;;
  esac
}
