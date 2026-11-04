#!/usr/bin/env bash
# Stubbed harness for the deploy shell boundary.
#
# Drives the committed deploy scripts from the outside with fake `ssh`, `scp`,
# `docker`, and `curl` commands. Nothing here touches a real host, registry, or
# container. Run with `bash scripts/test-deploy.sh`.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="$ROOT/scripts/deploy/validate-config.sh"
CLEANUP="$ROOT/scripts/deploy/cleanup-token.sh"

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

reset() {
  rm -rf "$STUB_DIR" "$HOME_DIR" "$SERVER_DIR"
  mkdir -p "$STUB_DIR" "$HOME_DIR/.ssh" "$SERVER_DIR"
  : > "$CALL_LOG"
  : > "$OUTPUT"
  printf 'dummy-key\n' > "$HOME_DIR/.ssh/id_ed25519"
  chmod 600 "$HOME_DIR/.ssh/id_ed25519"

  cat > "$STUB_DIR/ssh" <<EOF
#!/usr/bin/env bash
printf 'ssh %s\n' "\$*" >> "$CALL_LOG"
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
exit 0
EOF

  cat > "$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$CALL_LOG"
exit 0
EOF

  chmod 755 "$STUB_DIR/ssh" "$STUB_DIR/scp" "$STUB_DIR/docker" "$STUB_DIR/curl"
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

for name in IMAGE_TAG IMAGE_REPOSITORY DEPLOY_PATH SSH_HOST SSH_PORT SSH_USER PORT SSH_PRIVATE_KEY SSH_KNOWN_HOSTS; do
  reset
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

reset
if ! run_validate ""; then
  fail_case "complete configuration" "expected exit 0: $(tr '\n' ' ' <"$OUTPUT")"
elif ! grep -Fq 'Deploying ghcr.io/zapihq/docs.zapihq.com:sha-1a2b3c4 to /opt/zapi-docs' "$OUTPUT"; then
  fail_case "complete configuration" "missing success line: $(tr '\n' ' ' <"$OUTPUT")"
elif ! assert_no_remote_calls "complete configuration"; then
  :
else
  pass "complete configuration passes without remote calls"
fi

# --- Cleanup: only the staged token is removed, best-effort. ----------------

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

assert_server_files_untouched() {
  local label="$1"
  if ! cmp -s "$TMP_DIR/env.before" "$SERVER_DIR/.env"; then
    fail_case "$label" "operator .env changed or was removed"
    return 1
  fi
  if ! cmp -s "$TMP_DIR/compose.before" "$SERVER_DIR/compose.yml"; then
    fail_case "$label" "compose.yml changed or was removed"
    return 1
  fi
  if ! cmp -s "$TMP_DIR/image-env.before" "$SERVER_DIR/.image.env"; then
    fail_case "$label" ".image.env changed or was removed"
    return 1
  fi
  if ! cmp -s "$TMP_DIR/keep.before" "$SERVER_DIR/keep.txt"; then
    fail_case "$label" "keep.txt changed or was removed"
    return 1
  fi
  if ! cmp -s "$TMP_DIR/token-bak.before" "$SERVER_DIR/.ghcr-token.bak"; then
    fail_case "$label" ".ghcr-token.bak changed or was removed"
    return 1
  fi
}

assert_only_token_targeted() {
  local label="$1"
  if ! grep -Fq 'rm -f --' "$CALL_LOG"; then
    fail_case "$label" "no token removal was attempted: $(tr '\n' ' ' <"$CALL_LOG")"
    return 1
  fi
  if ! grep -Fq '.ghcr-token' "$CALL_LOG"; then
    fail_case "$label" "the remote command did not name the staged token"
    return 1
  fi
  if grep -Eq '^(scp|docker|curl) ' "$CALL_LOG"; then
    fail_case "$label" "cleanup called a command other than ssh"
    return 1
  fi
  if grep -Eq 'rm -f -- .*\.env|rm -f -- .*compose\.yml' "$CALL_LOG"; then
    fail_case "$label" "cleanup targeted a file other than the staged token"
    return 1
  fi
}

cleanup_case() {
  local label="$1"
  local token_expected="$2"
  local warning_expected="$3"

  reset
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

reset
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

  reset
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

reset
prepare_server
rm -f "$HOME_DIR/.ssh/id_ed25519"

if ! run_cleanup ""; then
  fail_case "cleanup without a prepared key" "cleanup exited non-zero: $(tr '\n' ' ' <"$OUTPUT")"
elif [ ! -e "$SERVER_DIR/.ghcr-token" ]; then
  fail_case "cleanup without a prepared key" "token was removed without a key"
elif ! assert_server_files_untouched "cleanup without a prepared key"; then
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

  reset
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
