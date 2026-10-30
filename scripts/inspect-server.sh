#!/usr/bin/env bash
# Temporary: read production state before the container cutover (#34).
# Prints only the facts the cutover depends on. Removed before merge.
set -Eeuo pipefail

install -m 700 -d ~/.ssh
printf '%s\n' "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
printf '%s\n' "$SSH_KNOWN_HOSTS" > ~/.ssh/known_hosts
chmod 644 ~/.ssh/known_hosts

SSH=(ssh -i ~/.ssh/id_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=~/.ssh/known_hosts -p "$SSH_PORT" "$SSH_USER@$SSH_HOST")

"${SSH[@]}" 'bash -s' <<'REMOTE'
set -uo pipefail
section() { printf '\n===== %s =====\n' "$1"; }

section "identity"
id
groups

section "docker"
docker --version || true
docker compose version || true
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true

section "sudo"
sudo -n -l 2>&1 || true

section "systemd"
systemctl is-active zapi-docs 2>&1 || true
systemctl is-enabled zapi-docs 2>&1 || true
systemctl cat zapi-docs 2>&1 || true

section "port 3002"
ss -lntp 2>/dev/null | grep -E ':3002\b' || true

section "paths"
ls -ld /opt /opt/zapi-docs 2>&1 || true
ls -la /opt/zapi-docs 2>&1 || true
ls -la /var/www/zapi-docs 2>&1 || true
ls -la /var/www/zapi-docs/shared 2>&1 || true

section "runtime env keys (values redacted)"
for f in /opt/zapi-docs/.env /var/www/zapi-docs/shared/.env.production; do
  echo "--- $f"
  if [ -r "$f" ]; then
    stat -c '%a %U:%G %n' "$f"
    sed -E 's/=.*/=<redacted>/' "$f"
  else
    echo "not readable"
  fi
done

section "nginx docs server block"
for f in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
  [ -f "$f" ] || continue
  if grep -q 'docs\.zapihq\.com' "$f" 2>/dev/null; then
    echo "--- $f"
    grep -nE 'server_name|listen|proxy_pass|auth_basic|ssl_certificate|access_log|error_log' "$f" || true
  fi
done
sudo -n nginx -t 2>&1 || true

section "loopback health"
curl -sS -m 5 -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3002/api/health || true

section "disk"
df -h / | tail -n 1
REMOTE
