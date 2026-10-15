#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_ID="${GITHUB_SHA}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"

ssh ${SSH_OPTIONS} -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" \
  "APP_NAME='${APP_NAME}' GITHUB_SHA='${GITHUB_SHA}' RELEASE_ID='${RELEASE_ID}' DEPLOY_PATH='${DEPLOY_PATH}' SERVICE_NAME='${SERVICE_NAME}' KEEP_RELEASES='${KEEP_RELEASES}' bash -s" <<'EOF'
set -Eeuo pipefail

RELEASES_DIR="${DEPLOY_PATH}/releases"
SHARED_DIR="${DEPLOY_PATH}/shared"
CURRENT_LINK="${DEPLOY_PATH}/current"
RELEASE_DIR="${RELEASES_DIR}/${RELEASE_ID}"
ARCHIVE_PATH="/tmp/${APP_NAME}-${GITHUB_SHA}.tar.gz"

install -m 755 -d "${RELEASES_DIR}" "${SHARED_DIR}" "${RELEASE_DIR}"
tar -xzf "${ARCHIVE_PATH}" -C "${RELEASE_DIR}"
rm -f "${ARCHIVE_PATH}"

if [ -f "${SHARED_DIR}/.env.production" ]; then
  ln -sfn "${SHARED_DIR}/.env.production" "${RELEASE_DIR}/.env.production"
fi

ln -sfn "${RELEASE_DIR}" "${CURRENT_LINK}"
sudo -n systemctl restart "${SERVICE_NAME}"
sudo -n systemctl is-active --quiet "${SERVICE_NAME}"

cd "${RELEASES_DIR}"
ls -1dt */ | tail -n +$((KEEP_RELEASES + 1)) | xargs -r rm -rf --
EOF
