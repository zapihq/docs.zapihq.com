#!/usr/bin/env bash
# The remote half of a deploy, streamed to the host by bundle.sh and run with
# `bash -s`. The same file can be run directly from a checkout for a manual
# rehearsal; it then sources the libraries bundle.sh would have inlined.
#
# The deploy group arrives in the environment, set by the workflow:
#   IMAGE_TAG, IMAGE_REPOSITORY, IMAGE_SOURCE, DEPLOY_PATH, PORT, GHCR_USER
#
# The staged registry token is already at ${DEPLOY_PATH}/.ghcr-token. It is
# removed on every exit path, successful or not.
set -Eeuo pipefail

if ! declare -F wait_for_health >/dev/null || ! declare -F classify_registry_error >/dev/null; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=../lib/health.sh
  source "$script_dir/../lib/health.sh"
  # shellcheck source=../lib/registry-error.sh
  source "$script_dir/../lib/registry-error.sh"
fi

fail() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

cd "$DEPLOY_PATH" || fail "missing deploy directory: $DEPLOY_PATH"

# deploy_doc is not in the docker group: that is an implicit root grant. The
# narrow sudoers rule allows exactly this binary instead.
DOCKER=(sudo -n /usr/bin/docker)

# The registry credential is the run's short-lived token, staged by the
# workflow as a file so it never reaches a process list. Remove it on every
# exit path, including failures before login.
TOKEN_FILE=.ghcr-token
logout() {
  "${DOCKER[@]}" logout ghcr.io >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE"
}
trap logout EXIT

[ -f compose.yml ] || fail "compose.yml was not synced"
[ -f .env ] || fail "missing operator-owned env file: $DEPLOY_PATH/.env"
[ -f "$TOKEN_FILE" ] || fail "missing staged registry token"

mode="$(stat -c '%a' .env)"
[ "$mode" = "600" ] || fail "$DEPLOY_PATH/.env must be mode 600, found $mode"

"${DOCKER[@]}" version >/dev/null 2>&1 ||
  fail "deploy user cannot run docker; add the NOPASSWD /usr/bin/docker rule"

# Keep the values out of the compose interpolation environment: the file is the
# single source, so a rollback cannot be overridden by a stale exported tag.
TAG="$IMAGE_TAG"
HOST_PORT="$PORT"
unset IMAGE_TAG PORT

# sudo resets the environment, so the compose variables live in a CI-owned
# interpolation file rather than being passed through the shell. It carries no
# secrets.
write_image_env() {
  printf 'IMAGE_TAG=%s\nPORT=%s\n' "$1" "$HOST_PORT" > .image.env
}
write_image_env "$TAG"
chmod 644 .image.env
COMPOSE=("${DOCKER[@]}" compose --env-file .image.env)

echo "Logging in to ghcr.io as $GHCR_USER"
"${DOCKER[@]}" login ghcr.io --username "$GHCR_USER" --password-stdin < "$TOKEN_FILE" >/dev/null ||
  fail "registry login failed"
rm -f "$TOKEN_FILE"

# Record what is running before anything can change it, so a failed rollback
# can say what stayed live and restore the interpolation file to match.
previous_image="$("${DOCKER[@]}" inspect --format '{{.Config.Image}}' zapi-docs 2>/dev/null || true)"
previous_tag="${previous_image##*:}"
echo "Previous tag: ${previous_tag:-none}"

# A pull failure is the normal outcome of a mistyped or inaccessible tag. It
# must name the reason and leave the running container alone.
echo "Pulling $IMAGE_REPOSITORY:$TAG"
pull_ok=1
pull_output="$("${COMPOSE[@]}" pull 2>&1)" || pull_ok=0
printf '%s\n' "$pull_output"
if [ "$pull_ok" -eq 0 ]; then
  if [ -n "$previous_tag" ]; then
    write_image_env "$previous_tag"
    outcome="the running container (${previous_tag}) is untouched"
  else
    # Leave no interpolation file naming a tag that does not exist.
    rm -f .image.env
    outcome="no container was running"
  fi
  case "$(classify_registry_error "$pull_output")" in
    # GHCR says "denied" both for a tag that is missing from a private package
    # and for a token that cannot read it, so the message must not claim which
    # of the two it was.
    auth)
      fail "cannot pull ${IMAGE_REPOSITORY}:${TAG}: the tag is missing or the token cannot read it; ${outcome}"
      ;;
    missing)
      fail "image tag '${TAG}' is not published in ${IMAGE_REPOSITORY}; ${outcome}"
      ;;
    *)
      fail "pull of ${IMAGE_REPOSITORY}:${TAG} failed; ${outcome}"
      ;;
  esac
fi

# Restore the tag that was running before this deploy. The reason a restore was
# skipped or failed is recorded for the caller, so a broken restore cannot hide
# behind the original error or claim to have restored something it did not.
restore_reason=""
restore_previous() {
  if [ -z "$previous_tag" ]; then
    restore_reason="no previous container to restore"
    return 1
  fi
  if [ "$previous_tag" = "$TAG" ]; then
    restore_reason="the previous container was already ${TAG}"
    return 1
  fi
  echo "Restoring $previous_tag"
  write_image_env "$previous_tag"
  if "${COMPOSE[@]}" up --detach --wait --wait-timeout 90; then
    return 0
  fi
  restore_reason="restoring ${previous_tag} failed"
  return 1
}

restore_on_failure() {
  if restore_previous; then
    fail "$1; restored $previous_tag"
  fi
  fail "$1; ${restore_reason}"
}

echo "Replacing the running container with $TAG"
if ! "${COMPOSE[@]}" up --detach --wait --wait-timeout 90; then
  "${COMPOSE[@]}" logs --tail 100 app || true
  restore_on_failure "new container unhealthy"
fi

# The tag in the log has to describe the container that is actually running,
# not the one that was requested.
running_image="$("${DOCKER[@]}" inspect --format '{{.Config.Image}}' zapi-docs)"
running_tag="${running_image##*:}"
if [ "$running_tag" != "$TAG" ]; then
  restore_on_failure "container is running '${running_tag}', expected '${TAG}'"
fi

# Health is a contract, not a container-state detail: speak HTTP to it.
if ! body="$(wait_for_health "$HOST_PORT" 30)"; then
  restore_on_failure "GET /api/health returned '${body}', expected '{\"status\":\"ok\"}'"
fi

echo "Pruning images older than seven days"
"${DOCKER[@]}" image prune --all --force \
  --filter "until=168h" \
  --filter "label=org.opencontainers.image.source=$IMAGE_SOURCE" >/dev/null || true

echo "Live tag: $TAG"
echo "Live image: $IMAGE_REPOSITORY:$TAG"
