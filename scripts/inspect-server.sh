#!/usr/bin/env bash
# Temporary: read production state before the container cutover (#34).
# Read-only. Removed before merge.
set -Eeuo pipefail

install -m 700 -d ~/.ssh
printf '%s\n' "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
printf '%s\n' "$SSH_KNOWN_HOSTS" > ~/.ssh/known_hosts
chmod 644 ~/.ssh/known_hosts

SSH=(ssh -i ~/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=~/.ssh/known_hosts -p "$SSH_PORT" "$SSH_USER@$SSH_HOST")

"${SSH[@]}" 'bash -s' <<'REMOTE'
set -uo pipefail
section() { printf '\n===== %s =====\n' "$1"; }

section "identity"
id
groups

section "sudo"
sudo -n -l 2>&1 || true

section "docker via sudo"
sudo -n /usr/bin/docker version 2>&1 || true
sudo -n /usr/bin/docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1 || true

section "systemd"
systemctl is-active zapi-docs 2>&1 || true
systemctl is-enabled zapi-docs 2>&1 || true

section "deploy path"
ls -ld /opt/zapi-docs 2>&1 || true
ls -la /opt/zapi-docs 2>&1 || true
if [ -f /opt/zapi-docs/.env ]; then
  stat -c '%a %U:%G %n' /opt/zapi-docs/.env
  cut -d= -f1 /opt/zapi-docs/.env
fi
if [ -f /opt/zapi-docs/.image.env ]; then
  stat -c '%a %U:%G %n' /opt/zapi-docs/.image.env
  cat /opt/zapi-docs/.image.env
fi

section "nginx docs upstream"
grep -nE 'server_name|proxy_pass|auth_basic' /etc/nginx/sites-enabled/docs.zapihq.com 2>&1 || true

section "loopback health"
curl -sS -m 5 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3002/api/health || true
REMOTE
