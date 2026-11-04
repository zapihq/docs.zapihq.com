#!/usr/bin/env bash
# Stubbed harness for the deploy shell boundary.
#
# Drives the committed deploy scripts from the outside with fake `ssh`, `scp`,
# `sudo`, `docker`, `curl`, `stat`, and `sleep` commands. Nothing here touches a
# real host, registry, or container. Run with `bash scripts/test-deploy.sh`.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="$ROOT/scripts/deploy/validate-config.sh"
CLEANUP="$ROOT/scripts/deploy/cleanup-token.sh"
RESOLVE="$ROOT/scripts/deploy/resolve-image.sh"
CONNECTION="$ROOT/scripts/deploy/connection.sh"
PREPARE_SSH="$ROOT/scripts/deploy/prepare-ssh.sh"
BUNDLE="$ROOT/scripts/deploy/bundle.sh"

# The probe contract shared by the container seam and the deploy job.
source "$ROOT/scripts/lib/health.sh"

TMP_DIR="$(mktemp -d)"
STUB_DIR="$TMP_DIR/bin"
HOME_DIR="$TMP_DIR/home"
SERVER_DIR="$TMP_DIR/server"
CALL_LOG="$TMP_DIR/calls.log"
OUTPUT="$TMP_DIR/output.log"

PASS=0
FAIL=0
FAILED_CASES=""

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  printf 'ok - %s\n' "$1"
}

fail_case() {
  FAIL=$((FAIL + 1))
  FAILED_CASES="${FAILED_CASES}
  - ${1}: ${2}"
  printf 'not ok - %s: %s\n' "$1" "$2" >&2
}

reset_fixture() {
  rm -rf "$STUB_DIR" "$HOME_DIR" "$SERVER_DIR"
  mkdir -p "$STUB_DIR" "$HOME_DIR/.ssh" "$SERVER_DIR"
  : > "$CALL_LOG"
  : > "$OUTPUT"
  printf 'dummy-key\n' > "$HOME_DIR/.ssh/id_ed25519"
  chmod 600 "$HOME_DIR/.ssh/id_ed25519"

  cat > "$STUB_DIR/ssh" <<EOF
#!/usr/bin/env bash
printf 'ssh %s\n' "\$*" >> "$CALL_LOG"
printf 'remote %s\n' "\${!#}" >> "$CALL_LOG"
if [ "\${STUB_SSH_FAIL:-0}" != "0" ]; then
  exit "\$STUB_SSH_FAIL"
fi
cmd="\${!#}"
case "\$cmd" in
  'rm -f -- '*)
    eval "\$cmd"
    ;;
esac
exit 0
EOF

  cat > "$STUB_DIR/scp" <<EOF
#!/usr/bin/env bash
printf 'scp %s\n' "\$*" >> "$CALL_LOG"
exit 0
EOF

  cat > "$STUB_DIR/docker" <<EOF
#!/usr/bin/env bash
printf 'docker %s\n' "\$*" >> "$CALL_LOG"

state_dir="$STUB_DIR/state"
mkdir -p "\$state_dir"

case " \$* " in
  *" login "*)
    cat >/dev/null
    exit "\${STUB_LOGIN_FAIL:-0}"
    ;;
  *" logout "*)
    exit 0
    ;;
  *" inspect "*)
    count_file="\$state_dir/inspect-count"
    count="\$(cat "\$count_file" 2>/dev/null || printf '0')"
    count=\$((count + 1))
    printf '%s' "\$count" > "\$count_file"
    if [ "\$count" -eq 1 ]; then
      printf '%s\n' "\${STUB_PREVIOUS_IMAGE:-}"
    else
      printf '%s\n' "\${STUB_RUNNING_IMAGE:-\${STUB_PREVIOUS_IMAGE:-}}"
    fi
    exit 0
    ;;
  *" pull "*)
    printf '%s\n' "\${STUB_PULL_OUTPUT:-}"
    exit "\${STUB_PULL_FAIL:-0}"
    ;;
  *" up "*)
    count_file="\$state_dir/up-count"
    count="\$(cat "\$count_file" 2>/dev/null || printf '0')"
    count=\$((count + 1))
    printf '%s' "\$count" > "\$count_file"
    if [ "\$count" -eq 1 ]; then
      exit "\${STUB_UP_FAIL_FIRST:-0}"
    fi
    exit 0
    ;;
  *" version "*)
    exit "\${STUB_DOCKER_VERSION_FAIL:-0}"
    ;;
  *" image prune "*)
    exit 0
    ;;
  *" logs "*)
    printf 'app  | boot failed\n'
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF

  # curl writes the body, then --write-out appends the status on its own line.
  cat > "$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$CALL_LOG"
if [ -n "\${STUB_HEALTH_BODY+x}" ]; then
  printf '%s' "\$STUB_HEALTH_BODY"
else
  printf '%s' '$HEALTH_BODY'
fi
printf '\n%s' "\${STUB_HEALTH_STATUS:-200}"
exit 0
EOF

  # sudo forwards the one docker binary the deploy account may run.
  cat > "$STUB_DIR/sudo" <<EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >> "$CALL_LOG"
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -n | --non-interactive) shift ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
cmd="\$1"
shift || true
case "\$cmd" in
  /usr/bin/docker) exec docker "\$@" ;;
  *) exec "\$cmd" "\$@" ;;
esac
EOF

  # Health retries must not spend real seconds in the harness.
  cat > "$STUB_DIR/sleep" <<EOF
#!/usr/bin/env bash
exit 0
EOF

  # Windows filesystems do not store modes, so the remote program's .env mode
  # check is driven through a stub.
  cat > "$STUB_DIR/stat" <<EOF
#!/usr/bin/env bash
printf 'stat %s\n' "\$*" >> "$CALL_LOG"
printf '%s\n' "\${STUB_ENV_MODE:-600}"
EOF

  chmod 755 "$STUB_DIR/ssh" "$STUB_DIR/scp" "$STUB_DIR/docker" "$STUB_DIR/curl" \
    "$STUB_DIR/sudo" "$STUB_DIR/sleep" "$STUB_DIR/stat"
}

base_env() {
  printf '%s\n' \
    IMAGE_TAG=sha-1a2b3c4 \
    IMAGE_REPOSITORY=ghcr.io/zapihq/docs.zapihq.com \
    DEPLOY_PATH=/opt/zapi-docs \
    SSH_HOST=docs.example.com \
    SSH_PORT=22 \
    SSH_USER=deploy_doc \
    PORT=3002 \
    SSH_PRIVATE_KEY=dummy-key \
    SSH_KNOWN_HOSTS=dummy-host-key
}

# Run the validation script with a clean environment, optionally setting one
# variable to an empty string. This mirrors the workflow, which exposes a
# missing secret as an empty environment variable. All other required settings
# are present.
run_validate() {
  local empty="${1:-}"
  local assignments=()
  local key value

  while IFS='=' read -r key value; do
    if [ "$key" = "$empty" ]; then
      assignments+=("$key=")
      continue
    fi
    assignments+=("$key=$value")
  done < <(base_env)

  env -i PATH="$STUB_DIR:$PATH" HOME="$HOME_DIR" "${assignments[@]}" \
    bash "$VALIDATE" >"$OUTPUT" 2>&1
}

assert_no_remote_calls() {
  if [ -s "$CALL_LOG" ]; then
    fail_case "$1" "unexpected remote command: $(tr '\n' ' ' <"$CALL_LOG")"
    return 1
  fi
}

# --- Validation: every required name is checked before any remote call. -----

for name in IMAGE_TAG IMAGE_REPOSITORY DEPLOY_PATH SSH_HOST SSH_PORT SSH_USER SSH_PRIVATE_KEY SSH_KNOWN_HOSTS; do
  reset_fixture
  if run_validate "$name"; then
    fail_case "missing $name" "expected a non-zero exit"
    continue
  fi

  expected="::error::Missing deploy configuration: $name"
  if ! grep -Fq "$expected" "$OUTPUT"; then
    fail_case "missing $name" "missing '${expected}' in output: $(tr '\n' ' ' <"$OUTPUT")"
    continue
  fi

  assert_no_remote_calls "missing $name" || continue
  pass "missing $name fails at validation"
done

# --- Validation: complete configuration passes without touching the host. ---

reset_fixture
if ! run_validate ""; then
  fail_case "complete configuration" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif ! grep -Fq 'Deploying ghcr.io/zapihq/docs.zapihq.com:sha-1a2b3c4 to /opt/zapi-docs' "$OUTPUT"; then
  fail_case "complete configuration" "missing success line: $(tr '\n' ' ' <"$OUTPUT")"
elif ! assert_no_remote_calls "complete configuration"; then
  :
else
  pass "complete configuration passes without remote calls"
fi

# PORT is defaulted by the workflow before validation, so an empty PORT must
# still pass: the default is what supplies it.
reset_fixture
if ! run_validate "PORT"; then
  fail_case "empty PORT" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif ! grep -Fq 'Deploying ghcr.io/zapihq/docs.zapihq.com:sha-1a2b3c4 to /opt/zapi-docs' "$OUTPUT"; then
  fail_case "empty PORT" "missing success line: $(tr '\n' ' ' <"$OUTPUT")"
elif ! assert_no_remote_calls "empty PORT"; then
  :
else
  pass "empty PORT passes validation with the workflow default"
fi

# --- Resolve image: one image group, written once for later steps. ----------

# Run the tag resolver with a clean environment and a fresh GITHUB_ENV file.
run_resolve() {
  local requested="$1"
  local built="$2"

  : > "$TMP_DIR/github-env"
  env -i \
    "PATH=$STUB_DIR:$PATH" \
    "HOME=$HOME_DIR" \
    "GITHUB_ENV=$TMP_DIR/github-env" \
    "GITHUB_REPOSITORY=ZAPIHQ/docs.zapihq.com" \
    "GITHUB_SERVER_URL=https://github.com" \
    "REQUESTED_TAG=$requested" \
    "BUILT_TAG=$built" \
    bash "$RESOLVE" >"$OUTPUT" 2>&1
}

write_expected_image_group() {
  printf 'IMAGE_TAG=%s\nIMAGE_REPOSITORY=ghcr.io/zapihq/docs.zapihq.com\nIMAGE_SOURCE=https://github.com/ZAPIHQ/docs.zapihq.com\n' \
    "$1" > "$TMP_DIR/github-env.expected"
}

# A dispatch carrying a tag deploys that tag, whatever this run built.
reset_fixture
write_expected_image_group "sha-requested"
if ! run_resolve "sha-requested" "sha-built"; then
  fail_case "resolve: requested tag wins" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif ! cmp -s "$TMP_DIR/github-env.expected" "$TMP_DIR/github-env"; then
  fail_case "resolve: requested tag wins" "image group was: $(tr '\n' ' ' <"$TMP_DIR/github-env")"
elif ! grep -Fq 'Deploy mode: rollback to an earlier published tag' "$OUTPUT"; then
  fail_case "resolve: requested tag wins" "missing rollback notice: $(tr '\n' ' ' <"$OUTPUT")"
elif ! grep -Fq '::notice title=Deploy target::ghcr.io/zapihq/docs.zapihq.com:sha-requested' "$OUTPUT"; then
  fail_case "resolve: requested tag wins" "missing deploy-target notice: $(tr '\n' ' ' <"$OUTPUT")"
else
  pass "resolve: requested tag wins and writes the image group"
fi

# An empty dispatch input deploys this run's build.
reset_fixture
write_expected_image_group "sha-built"
if ! run_resolve "" "sha-built"; then
  fail_case "resolve: built tag when no tag is requested" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif ! cmp -s "$TMP_DIR/github-env.expected" "$TMP_DIR/github-env"; then
  fail_case "resolve: built tag when no tag is requested" "image group was: $(tr '\n' ' ' <"$TMP_DIR/github-env")"
elif ! grep -Fq "Deploy mode: this run's build" "$OUTPUT"; then
  fail_case "resolve: built tag when no tag is requested" "missing build notice: $(tr '\n' ' ' <"$OUTPUT")"
else
  pass "resolve: an empty request uses this run's build"
fi

# Neither input exists: fail before writing anything later steps would trust.
reset_fixture
if run_resolve "" ""; then
  fail_case "resolve: no tag at all" "expected a non-zero exit"
elif ! grep -Fq '::error::No image tag: pass image_tag, or deploy a commit that publishes one.' "$OUTPUT"; then
  fail_case "resolve: no tag at all" "missing error: $(tr '\n' ' ' <"$OUTPUT")"
elif [ -s "$TMP_DIR/github-env" ]; then
  fail_case "resolve: no tag at all" "wrote an image group anyway: $(tr '\n' ' ' <"$TMP_DIR/github-env")"
else
  pass "resolve: no tag at all fails without writing the image group"
fi

# The tag is carried into a remote shell and compose, so the grammar is a gate.
reset_fixture
if run_resolve "not a tag" "sha-built"; then
  fail_case "resolve: invalid tag" "expected a non-zero exit"
elif ! grep -Fq "::error::Invalid image_tag 'not a tag': expected a Docker tag such as sha-1a2b3c4." "$OUTPUT"; then
  fail_case "resolve: invalid tag" "missing error: $(tr '\n' ' ' <"$OUTPUT")"
elif [ -s "$TMP_DIR/github-env" ]; then
  fail_case "resolve: invalid tag" "wrote an image group anyway: $(tr '\n' ' ' <"$TMP_DIR/github-env")"
else
  pass "resolve: an invalid tag fails without writing the image group"
fi

# --- Connection: one SSH/SCP seam owns the connection group. ----------------

SSH_OPTIONS_FIXTURE="-o BatchMode=yes -o StrictHostKeyChecking=yes"

# Run the connection seam with a clean environment, optionally omitting one
# connection setting.
run_connection() {
  local skip="${1:-}"
  shift || true
  local assignments=(
    "HOME=$HOME_DIR"
    "PATH=$STUB_DIR:$PATH"
    "SSH_HOST=docs.example.com"
    "SSH_PORT=2222"
    "SSH_USER=deploy_doc"
    "SSH_OPTIONS=$SSH_OPTIONS_FIXTURE"
  )
  local filtered=() item key

  for item in "${assignments[@]}"; do
    key="${item%%=*}"
    [ "$key" = "$skip" ] && continue
    filtered+=("$item")
  done

  env -i "${filtered[@]}" bash "$CONNECTION" "$@" >"$OUTPUT" 2>&1
}

reset_fixture
if ! run_connection "" run "printf hello"; then
  fail_case "connection: run" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif ! grep -Fxq "ssh -i $HOME_DIR/.ssh/id_ed25519 $SSH_OPTIONS_FIXTURE -p 2222 deploy_doc@docs.example.com printf hello" "$CALL_LOG"; then
  fail_case "connection: run" "ssh call was: $(tr '\n' ' ' <"$CALL_LOG")"
elif ! grep -Fxq 'remote printf hello' "$CALL_LOG"; then
  fail_case "connection: run" "remote command was not carried: $(tr '\n' ' ' <"$CALL_LOG")"
else
  pass "connection: run carries the shared options, key, port and target"
fi

reset_fixture
printf 'services: {}\n' > "$TMP_DIR/compose.local"
if ! run_connection "" copy "$TMP_DIR/compose.local" "$SERVER_DIR/compose.yml"; then
  fail_case "connection: copy" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif ! grep -Fxq "scp -i $HOME_DIR/.ssh/id_ed25519 $SSH_OPTIONS_FIXTURE -P 2222 $TMP_DIR/compose.local deploy_doc@docs.example.com:$SERVER_DIR/compose.yml" "$CALL_LOG"; then
  fail_case "connection: copy" "scp call was: $(tr '\n' ' ' <"$CALL_LOG")"
elif grep -q '^ssh ' "$CALL_LOG"; then
  fail_case "connection: copy" "copy used ssh: $(tr '\n' ' ' <"$CALL_LOG")"
else
  pass "connection: copy carries the shared options, key, port and target"
fi

# Incomplete connection settings are a configuration error (exit 2), and they
# must stop before either command runs.
for name in SSH_HOST SSH_PORT SSH_USER; do
  reset_fixture
  run_connection "$name" run "printf hello"
  status=$?
  if [ "$status" -ne 2 ]; then
    fail_case "connection: missing $name" "expected exit 2, got ${status}: $(tr '\n' ' ' <"$OUTPUT")"
  elif [ -s "$CALL_LOG" ]; then
    fail_case "connection: missing $name" "called a remote command: $(tr '\n' ' ' <"$CALL_LOG")"
  elif ! grep -Fq "::error::Missing SSH configuration: $name" "$OUTPUT"; then
    fail_case "connection: missing $name" "missing error: $(tr '\n' ' ' <"$OUTPUT")"
  else
    pass "connection: missing $name exits 2 before any remote call"
  fi
done

reset_fixture
run_connection "SSH_HOST" copy "$TMP_DIR/compose.local" "$SERVER_DIR/compose.yml"
status=$?
if [ "$status" -ne 2 ]; then
  fail_case "connection: copy with missing SSH_HOST" "expected exit 2, got ${status}: $(tr '\n' ' ' <"$OUTPUT")"
elif [ -s "$CALL_LOG" ]; then
  fail_case "connection: copy with missing SSH_HOST" "called a remote command: $(tr '\n' ' ' <"$CALL_LOG")"
else
  pass "connection: copy with missing SSH_HOST exits 2 before any remote call"
fi

# --- Prepare SSH: the credential group is written with ssh's modes. ---------

# Windows filesystems report a fixed mode for every file, so only assert modes
# where the filesystem actually stores them (CI's Linux runner does).
modes_enforced() {
  local probe="$TMP_DIR/mode-probe"
  printf 'x' > "$probe"
  chmod 600 "$probe" 2>/dev/null || return 1
  [ "$(stat -c '%a' "$probe" 2>/dev/null)" = "600" ]
}

MODES_ENFORCED=no
if modes_enforced; then
  MODES_ENFORCED=yes
fi
MODE_NOTE=""
if [ "$MODES_ENFORCED" = "yes" ]; then
  MODE_NOTE=" with modes enforced"
fi

reset_fixture
rm -rf "$HOME_DIR/.ssh"
if ! env -i \
  "HOME=$HOME_DIR" \
  "PATH=$STUB_DIR:$PATH" \
  "SSH_PRIVATE_KEY=dummy-key-line1
dummy-key-line2" \
  "SSH_KNOWN_HOSTS=dummy-host-key" \
  bash "$PREPARE_SSH" >"$OUTPUT" 2>&1; then
  fail_case "prepare-ssh: writes credentials" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif [ ! -f "$HOME_DIR/.ssh/id_ed25519" ]; then
  fail_case "prepare-ssh: writes credentials" "deploy key was not written"
elif [ "$(cat "$HOME_DIR/.ssh/id_ed25519")" != "dummy-key-line1
dummy-key-line2" ]; then
  fail_case "prepare-ssh: writes credentials" "deploy key was: $(cat "$HOME_DIR/.ssh/id_ed25519")"
elif [ "$(cat "$HOME_DIR/.ssh/known_hosts")" != "dummy-host-key" ]; then
  fail_case "prepare-ssh: writes credentials" "known_hosts was: $(cat "$HOME_DIR/.ssh/known_hosts")"
elif [ "$MODES_ENFORCED" = "yes" ] && [ "$(stat -c '%a' "$HOME_DIR/.ssh/id_ed25519")" != "600" ]; then
  fail_case "prepare-ssh: writes credentials" "deploy key mode was $(stat -c '%a' "$HOME_DIR/.ssh/id_ed25519"), expected 600"
elif [ "$MODES_ENFORCED" = "yes" ] && [ "$(stat -c '%a' "$HOME_DIR/.ssh/known_hosts")" != "644" ]; then
  fail_case "prepare-ssh: writes credentials" "known_hosts mode was $(stat -c '%a' "$HOME_DIR/.ssh/known_hosts"), expected 644"
elif [ "$MODES_ENFORCED" = "yes" ] && [ "$(stat -c '%a' "$HOME_DIR/.ssh")" != "700" ]; then
  fail_case "prepare-ssh: writes credentials" ".ssh mode was $(stat -c '%a' "$HOME_DIR/.ssh"), expected 700"
else
  pass "prepare-ssh writes the key and known_hosts${MODE_NOTE}"
fi

# The deploy host fixture: CI-owned files, operator-owned files, and the
# transient token. None of the remote cases may change the operator's files.
prepare_server() {
  printf 'IMAGE_TAG=sha-old\nPORT=3002\n' > "$SERVER_DIR/.image.env"
  printf 'OPENROUTER_API_KEY=secret\n' > "$SERVER_DIR/.env"
  printf 'services:\n  app:\n    image: example\n' > "$SERVER_DIR/compose.yml"
  printf 'staged-token\n' > "$SERVER_DIR/.ghcr-token"
  printf 'operator-note\n' > "$SERVER_DIR/keep.txt"
  printf 'older-token\n' > "$SERVER_DIR/.ghcr-token.bak"
  chmod 600 "$SERVER_DIR/.env"
  cp "$SERVER_DIR/.env" "$TMP_DIR/env.before"
  cp "$SERVER_DIR/compose.yml" "$TMP_DIR/compose.before"
  cp "$SERVER_DIR/.image.env" "$TMP_DIR/image-env.before"
  cp "$SERVER_DIR/keep.txt" "$TMP_DIR/keep.before"
  cp "$SERVER_DIR/.ghcr-token.bak" "$TMP_DIR/token-bak.before"
}

# --- Health: one probe contract for the container seam and the deploy. ------

reset_fixture
if ! body="$(PATH="$STUB_DIR:$PATH" wait_for_health 3002 3)"; then
  fail_case "health: matching body at 200" "expected success, got '${body}'"
elif [ "$body" != "$HEALTH_BODY" ]; then
  fail_case "health: matching body at 200" "returned '${body}'"
elif ! grep -Fq 'curl --silent --max-time 5 --write-out' "$CALL_LOG"; then
  fail_case "health: matching body at 200" "probe was: $(tr '\n' ' ' <"$CALL_LOG")"
elif ! grep -Fq 'http://127.0.0.1:3002/api/health' "$CALL_LOG"; then
  fail_case "health: matching body at 200" "probe was: $(tr '\n' ' ' <"$CALL_LOG")"
elif [ "$(grep -c '^curl ' "$CALL_LOG")" != "1" ]; then
  fail_case "health: matching body at 200" "expected one request, saw $(grep -c '^curl ' "$CALL_LOG")"
else
  pass "health: a matching body returns ok for the requested port"
fi

# The status is part of the contract: a 204 with the right body is not healthy.
reset_fixture
if body="$(STUB_HEALTH_STATUS=204 PATH="$STUB_DIR:$PATH" wait_for_health 3002 3)"; then
  fail_case "health: matching body with a non-200 status" "expected failure"
elif [ "$body" != "$HEALTH_BODY" ]; then
  fail_case "health: matching body with a non-200 status" "returned '${body}', expected the last body"
elif [ "$(grep -c '^curl ' "$CALL_LOG")" != "3" ]; then
  fail_case "health: matching body with a non-200 status" "expected 3 attempts, saw $(grep -c '^curl ' "$CALL_LOG")"
else
  pass "health: a matching body with a non-200 status still fails"
fi

reset_fixture
if body="$(STUB_HEALTH_BODY='{"status":"degraded"}' PATH="$STUB_DIR:$PATH" wait_for_health 3002 3)"; then
  fail_case "health: mismatching body" "expected failure"
elif [ "$body" != '{"status":"degraded"}' ]; then
  fail_case "health: mismatching body" "returned '${body}', expected the last body"
elif [ "$(grep -c '^curl ' "$CALL_LOG")" != "3" ]; then
  fail_case "health: mismatching body" "expected 3 attempts, saw $(grep -c '^curl ' "$CALL_LOG")"
else
  pass "health: a mismatching body retries and reports the last body"
fi

# --- Deploy program: bundle.sh streams the remote program, stubs stand in ---
# for the host. Everything here drives the committed scripts as the workflow
# does: `bash bundle.sh | bash -s` with the deploy group in the environment.

reset_stub_state() {
  unset STUB_PREVIOUS_IMAGE STUB_RUNNING_IMAGE STUB_PULL_OUTPUT STUB_PULL_FAIL \
    STUB_UP_FAIL_FIRST STUB_DOCKER_VERSION_FAIL STUB_LOGIN_FAIL STUB_ENV_MODE \
    STUB_HEALTH_BODY STUB_HEALTH_STATUS
}

run_remote() {
  local tag="${REMOTE_TAG:-sha-1a2b3c4}"
  local repository="ghcr.io/zapihq/docs.zapihq.com"
  local assignments=(
    "PATH=$STUB_DIR:$PATH"
    "HOME=$HOME_DIR"
    "IMAGE_TAG=$tag"
    "IMAGE_REPOSITORY=$repository"
    "IMAGE_SOURCE=https://github.com/zapihq/docs.zapihq.com"
    "DEPLOY_PATH=$SERVER_DIR"
    "PORT=3002"
    "GHCR_USER=zapihq"
    "STUB_PREVIOUS_IMAGE=${STUB_PREVIOUS_IMAGE:-}"
    "STUB_RUNNING_IMAGE=${STUB_RUNNING_IMAGE:-$repository:$tag}"
    "STUB_PULL_OUTPUT=${STUB_PULL_OUTPUT:-}"
    "STUB_PULL_FAIL=${STUB_PULL_FAIL:-0}"
    "STUB_UP_FAIL_FIRST=${STUB_UP_FAIL_FIRST:-0}"
    "STUB_DOCKER_VERSION_FAIL=${STUB_DOCKER_VERSION_FAIL:-0}"
    "STUB_LOGIN_FAIL=${STUB_LOGIN_FAIL:-0}"
    "STUB_ENV_MODE=${STUB_ENV_MODE:-600}"
    "STUB_HEALTH_STATUS=${STUB_HEALTH_STATUS:-200}"
  )
  if [ -n "${STUB_HEALTH_BODY+x}" ]; then
    assignments+=("STUB_HEALTH_BODY=$STUB_HEALTH_BODY")
  fi

  env -i "${assignments[@]}" "BUNDLE=$BUNDLE" \
    bash -c 'bash "$BUNDLE" | bash -s' >"$OUTPUT" 2>&1
}

assert_remote_output() {
  local label="$1"
  local expected="$2"

  if ! grep -Fq "$expected" "$OUTPUT"; then
    fail_case "$label" "missing '${expected}': $(tr '\n' ' ' <"$OUTPUT")"
    return 1
  fi
}

assert_image_env_tag() {
  local label="$1"
  local tag="$2"

  printf 'IMAGE_TAG=%s\nPORT=3002\n' "$tag" > "$TMP_DIR/image-env.expected"
  if ! cmp -s "$TMP_DIR/image-env.expected" "$SERVER_DIR/.image.env"; then
    fail_case "$label" ".image.env was: $(tr '\n' ' ' <"$SERVER_DIR/.image.env" 2>/dev/null)"
    return 1
  fi
}

assert_token_removed() {
  local label="$1"

  if [ -e "$SERVER_DIR/.ghcr-token" ]; then
    fail_case "$label" "staged token still present"
    return 1
  fi
}

reset_fixture
prepare_server
reset_stub_state
if ! run_remote; then
  fail_case "remote: successful deploy" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif ! assert_remote_output "remote: successful deploy" 'Live tag: sha-1a2b3c4'; then
  :
elif ! assert_remote_output "remote: successful deploy" 'Live image: ghcr.io/zapihq/docs.zapihq.com:sha-1a2b3c4'; then
  :
elif ! assert_image_env_tag "remote: successful deploy" "sha-1a2b3c4"; then
  :
elif ! assert_token_removed "remote: successful deploy"; then
  :
elif ! grep -Fq 'curl --silent --max-time 5 --write-out' "$CALL_LOG"; then
  fail_case "remote: successful deploy" "health probe was: $(tr '\n' ' ' <"$CALL_LOG")"
elif ! grep -Fq 'http://127.0.0.1:3002/api/health' "$CALL_LOG"; then
  fail_case "remote: successful deploy" "health probe was: $(tr '\n' ' ' <"$CALL_LOG")"
elif ! grep -Fq 'docker logout ghcr.io' "$CALL_LOG"; then
  fail_case "remote: successful deploy" "registry session was not logged out"
elif ! grep -Fq 'docker image prune --all --force --filter until=168h --filter label=org.opencontainers.image.source=https://github.com/zapihq/docs.zapihq.com' "$CALL_LOG"; then
  fail_case "remote: successful deploy" "image prune was: $(tr '\n' ' ' <"$CALL_LOG")"
else
  pass "remote: a healthy pull replaces the container and reports the live tag"
fi

# A denied pull is the private-package case: the tag may be missing or the
# token may be unable to read it, so the message names both.
reset_fixture
prepare_server
reset_stub_state
STUB_PREVIOUS_IMAGE="ghcr.io/zapihq/docs.zapihq.com:sha-old"
STUB_PULL_OUTPUT="Error response from daemon: denied: requested access to the resource is denied"
STUB_PULL_FAIL=1
if run_remote; then
  fail_case "remote: pull denied" "expected a non-zero exit"
elif ! assert_remote_output "remote: pull denied" \
  "cannot pull ghcr.io/zapihq/docs.zapihq.com:sha-1a2b3c4: the tag is missing or the token cannot read it; the running container (sha-old) is untouched"; then
  :
elif ! assert_image_env_tag "remote: pull denied" "sha-old"; then
  :
elif ! assert_token_removed "remote: pull denied"; then
  :
else
  pass "remote: a denied pull keeps the running tag and restores .image.env"
fi

# A missing tag on a host with no container leaves no interpolation file.
reset_fixture
prepare_server
reset_stub_state
STUB_PULL_OUTPUT="manifest unknown"
STUB_PULL_FAIL=1
if run_remote; then
  fail_case "remote: pull manifest unknown" "expected a non-zero exit"
elif ! assert_remote_output "remote: pull manifest unknown" \
  "image tag 'sha-1a2b3c4' is not published in ghcr.io/zapihq/docs.zapihq.com; no container was running"; then
  :
elif [ -e "$SERVER_DIR/.image.env" ]; then
  fail_case "remote: pull manifest unknown" ".image.env was left naming a tag that does not exist"
elif ! assert_token_removed "remote: pull manifest unknown"; then
  :
else
  pass "remote: an unpublished tag on a bare host removes .image.env"
fi

# Anything else is a generic pull failure, still naming what stayed live.
reset_fixture
prepare_server
reset_stub_state
STUB_PREVIOUS_IMAGE="ghcr.io/zapihq/docs.zapihq.com:sha-old"
STUB_PULL_OUTPUT="network timeout"
STUB_PULL_FAIL=1
if run_remote; then
  fail_case "remote: pull other error" "expected a non-zero exit"
elif ! assert_remote_output "remote: pull other error" \
  "pull of ghcr.io/zapihq/docs.zapihq.com:sha-1a2b3c4 failed; the running container (sha-old) is untouched"; then
  :
elif ! assert_image_env_tag "remote: pull other error" "sha-old"; then
  :
else
  pass "remote: an unclassified pull failure reports the generic reason"
fi

# A container that does not come up healthy prints its logs and restores the
# tag that was running.
reset_fixture
prepare_server
reset_stub_state
STUB_PREVIOUS_IMAGE="ghcr.io/zapihq/docs.zapihq.com:sha-old"
STUB_UP_FAIL_FIRST=1
if run_remote; then
  fail_case "remote: unhealthy container" "expected a non-zero exit"
elif ! assert_remote_output "remote: unhealthy container" "new container unhealthy; restored sha-old"; then
  :
elif ! assert_remote_output "remote: unhealthy container" 'app  | boot failed'; then
  :
elif ! assert_image_env_tag "remote: unhealthy container" "sha-old"; then
  :
else
  pass "remote: an unhealthy container restores the previous tag"
fi

# Health is the running container, not the requested tag: a mismatch restores.
reset_fixture
prepare_server
reset_stub_state
STUB_PREVIOUS_IMAGE="ghcr.io/zapihq/docs.zapihq.com:sha-old"
STUB_RUNNING_IMAGE="ghcr.io/zapihq/docs.zapihq.com:sha-other"
if run_remote; then
  fail_case "remote: running tag mismatch" "expected a non-zero exit"
elif ! assert_remote_output "remote: running tag mismatch" \
  "container is running 'sha-other', expected 'sha-1a2b3c4'; restored sha-old"; then
  :
elif ! assert_image_env_tag "remote: running tag mismatch" "sha-old"; then
  :
else
  pass "remote: a running tag mismatch restores the previous tag"
fi

# Health is a contract, not just container state: a wrong body restores too.
reset_fixture
prepare_server
reset_stub_state
STUB_PREVIOUS_IMAGE="ghcr.io/zapihq/docs.zapihq.com:sha-old"
STUB_HEALTH_BODY='{"status":"degraded"}'
if run_remote; then
  fail_case "remote: wrong health body" "expected a non-zero exit"
elif ! assert_remote_output "remote: wrong health body" \
  "GET /api/health returned '{\"status\":\"degraded\"}', expected '${HEALTH_BODY}'; restored sha-old"; then
  :
elif ! assert_image_env_tag "remote: wrong health body" "sha-old"; then
  :
else
  pass "remote: a health body outside the contract restores the previous tag"
fi

# The operator-owned files are a precondition: fail before compose runs.
reset_fixture
prepare_server
reset_stub_state
rm -f "$SERVER_DIR/.env"
if run_remote; then
  fail_case "remote: missing .env" "expected a non-zero exit"
elif ! assert_remote_output "remote: missing .env" "missing operator-owned env file: $SERVER_DIR/.env"; then
  :
elif grep -Fq ' up ' "$CALL_LOG"; then
  fail_case "remote: missing .env" "compose up ran despite the missing file"
elif ! assert_token_removed "remote: missing .env"; then
  :
else
  pass "remote: a missing .env fails before compose and removes the token"
fi

reset_fixture
prepare_server
reset_stub_state
STUB_ENV_MODE=644
if run_remote; then
  fail_case "remote: wrong .env mode" "expected a non-zero exit"
elif ! assert_remote_output "remote: wrong .env mode" "$SERVER_DIR/.env must be mode 600, found 644"; then
  :
elif grep -Fq ' up ' "$CALL_LOG"; then
  fail_case "remote: wrong .env mode" "compose up ran despite the wrong mode"
elif ! assert_token_removed "remote: wrong .env mode"; then
  :
else
  pass "remote: a wrong .env mode fails before compose and removes the token"
fi

# The exit trap is the last line of defence for the staged token.
reset_fixture
prepare_server
reset_stub_state
rm -f "$SERVER_DIR/compose.yml"
if run_remote; then
  fail_case "remote: early failure" "expected a non-zero exit"
elif ! assert_remote_output "remote: early failure" 'compose.yml was not synced'; then
  :
elif ! assert_token_removed "remote: early failure"; then
  :
elif ! grep -Fq 'docker logout ghcr.io' "$CALL_LOG"; then
  fail_case "remote: early failure" "registry logout did not run"
else
  pass "remote: an early failure still removes the token through the trap"
fi

# --- Cleanup: only the staged token is removed, best-effort. ----------------

# Run the cleanup script with a clean environment, optionally omitting one
# connection setting.
run_cleanup() {
  local skip="${1:-}"
  local assignments=(
    "HOME=$HOME_DIR"
    "PATH=$STUB_DIR:$PATH"
    "DEPLOY_PATH=$SERVER_DIR"
    "SSH_HOST=docs.example.com"
    "SSH_PORT=22"
    "SSH_USER=deploy_doc"
    "SSH_OPTIONS=-o BatchMode=yes"
    "STUB_SSH_FAIL=${STUB_SSH_FAIL:-0}"
  )
  local filtered=()
  local item key

  for item in "${assignments[@]}"; do
    key="${item%%=*}"
    [ "$key" = "$skip" ] && continue
    filtered+=("$item")
  done

  env -i "${filtered[@]}" bash "$CLEANUP" >"$OUTPUT" 2>&1
}

assert_file_unchanged() {
  local before="$1"
  local after="$2"
  local description="$3"
  local label="$4"

  if ! cmp -s "$before" "$after"; then
    fail_case "$label" "${description} changed or was removed"
    return 1
  fi
}

assert_server_files_untouched() {
  local label="$1"
  local check_key="${2:-yes}"

  assert_file_unchanged "$TMP_DIR/env.before" "$SERVER_DIR/.env" "operator .env" "$label" || return 1
  assert_file_unchanged "$TMP_DIR/compose.before" "$SERVER_DIR/compose.yml" "compose.yml" "$label" || return 1
  assert_file_unchanged "$TMP_DIR/image-env.before" "$SERVER_DIR/.image.env" ".image.env" "$label" || return 1
  assert_file_unchanged "$TMP_DIR/keep.before" "$SERVER_DIR/keep.txt" "keep.txt" "$label" || return 1
  assert_file_unchanged "$TMP_DIR/token-bak.before" "$SERVER_DIR/.ghcr-token.bak" ".ghcr-token.bak" "$label" || return 1

  if [ "$check_key" = "yes" ] && [ ! -f "$HOME_DIR/.ssh/id_ed25519" ]; then
    fail_case "$label" "deploy key was removed"
    return 1
  fi
}

assert_only_token_targeted() {
  local label="$1"
  local expected="remote rm -f -- $SERVER_DIR/.ghcr-token"
  local remote_lines

  remote_lines="$(grep -c '^remote ' "$CALL_LOG" || true)"
  if [ "$remote_lines" != "1" ]; then
    fail_case "$label" "expected exactly one remote command, found ${remote_lines}: $(tr '\n' ' ' <"$CALL_LOG")"
    return 1
  fi
  if ! grep -Fxq "$expected" "$CALL_LOG"; then
    fail_case "$label" "remote command was not '${expected}': $(tr '\n' ' ' <"$CALL_LOG")"
    return 1
  fi
  if grep -Eq '^(scp|docker|curl) ' "$CALL_LOG"; then
    fail_case "$label" "cleanup called a command other than ssh"
    return 1
  fi
}

cleanup_case() {
  local label="$1"
  local token_expected="$2"
  local warning_expected="$3"

  reset_fixture
  prepare_server

  if ! run_cleanup ""; then
    fail_case "$label" "cleanup exited non-zero: $(tr '\n' ' ' <"$OUTPUT")"
    return
  fi
  if [ "$token_expected" = "gone" ] && [ -e "$SERVER_DIR/.ghcr-token" ]; then
    fail_case "$label" "staged token still present"
    return
  fi
  if [ "$token_expected" = "present" ] && [ ! -e "$SERVER_DIR/.ghcr-token" ]; then
    fail_case "$label" "staged token was removed"
    return
  fi
  assert_server_files_untouched "$label" || return
  assert_only_token_targeted "$label" || return

  if [ "$warning_expected" = "yes" ] && ! grep -Fq '::warning::' "$OUTPUT"; then
    fail_case "$label" "expected a warning: $(tr '\n' ' ' <"$OUTPUT")"
    return
  fi
  if [ "$warning_expected" = "no" ] && grep -Fq '::warning::' "$OUTPUT"; then
    fail_case "$label" "unexpected warning: $(tr '\n' ' ' <"$OUTPUT")"
    return
  fi

  pass "$label"
}

cleanup_case "cleanup removes the staged token on success" "gone" "no"

reset_fixture
prepare_server
rm -f "$SERVER_DIR/.ghcr-token"
if ! run_cleanup ""; then
  fail_case "cleanup with no staged token" "cleanup exited non-zero: $(tr '\n' ' ' <"$OUTPUT")"
elif [ -e "$SERVER_DIR/.ghcr-token" ]; then
  fail_case "cleanup with no staged token" "token unexpectedly exists"
elif ! assert_server_files_untouched "cleanup with no staged token"; then
  :
elif ! assert_only_token_targeted "cleanup with no staged token"; then
  :
else
  pass "cleanup with no staged token is idempotent"
fi

for failure in "1:remote failure" "255:SSH unreachable"; do
  code="${failure%%:*}"
  label="cleanup after ${failure#*:}"

  reset_fixture
  prepare_server
  STUB_SSH_FAIL="$code"

  if ! run_cleanup ""; then
    fail_case "$label" "cleanup turned the failure into a red step: $(tr '\n' ' ' <"$OUTPUT")"
    continue
  fi
  if [ ! -e "$SERVER_DIR/.ghcr-token" ]; then
    fail_case "$label" "token disappeared despite a failed SSH call"
    continue
  fi
  assert_server_files_untouched "$label" || continue
  assert_only_token_targeted "$label" || continue
  if ! grep -Fq '::warning::' "$OUTPUT"; then
    fail_case "$label" "expected a warning: $(tr '\n' ' ' <"$OUTPUT")"
    continue
  fi

  pass "$label exits 0 with a warning"
done
STUB_SSH_FAIL=0

reset_fixture
prepare_server
rm -f "$HOME_DIR/.ssh/id_ed25519"

if ! run_cleanup ""; then
  fail_case "cleanup without a prepared key" "cleanup exited non-zero: $(tr '\n' ' ' <"$OUTPUT")"
elif [ ! -e "$SERVER_DIR/.ghcr-token" ]; then
  fail_case "cleanup without a prepared key" "token was removed without a key"
elif [ -e "$HOME_DIR/.ssh/id_ed25519" ]; then
  fail_case "cleanup without a prepared key" "deploy key unexpectedly exists"
elif ! assert_server_files_untouched "cleanup without a prepared key" "no"; then
  :
elif [ -s "$CALL_LOG" ]; then
  fail_case "cleanup without a prepared key" "SSH was attempted: $(tr '\n' ' ' <"$CALL_LOG")"
elif ! grep -Fq '::warning::' "$OUTPUT"; then
  fail_case "cleanup without a prepared key" "expected a warning: $(tr '\n' ' ' <"$OUTPUT")"
else
  pass "cleanup without a prepared key skips with a warning"
fi

for name in DEPLOY_PATH SSH_HOST SSH_PORT SSH_USER; do
  label="cleanup with missing $name"

  reset_fixture
  prepare_server

  if ! run_cleanup "$name"; then
    fail_case "$label" "cleanup exited non-zero: $(tr '\n' ' ' <"$OUTPUT")"
    continue
  fi
  if [ ! -e "$SERVER_DIR/.ghcr-token" ]; then
    fail_case "$label" "token was removed with incomplete settings"
    continue
  fi
  assert_server_files_untouched "$label" || continue
  if [ -s "$CALL_LOG" ]; then
    fail_case "$label" "SSH was attempted: $(tr '\n' ' ' <"$CALL_LOG")"
    continue
  fi
  if ! grep -Fq '::warning::' "$OUTPUT"; then
    fail_case "$label" "expected a warning: $(tr '\n' ' ' <"$OUTPUT")"
    continue
  fi

  pass "$label skips with a warning"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'Failed cases:%s\n' "$FAILED_CASES" >&2
  exit 1
fi
