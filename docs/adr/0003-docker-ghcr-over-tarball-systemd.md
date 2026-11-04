# Production runs a private GHCR image under compose, not a tarball under systemd

Until this change, a deploy built the Next.js standalone output in GitHub
Actions, tarred it, copied the archive to the server, extracted it into
`/var/www/zapi-docs/releases/<release-id>`, repointed the `current` symlink,
and restarted the `zapi-docs` systemd unit on port 3002. The site worked, but
production was a directory tree on one machine. There was no artifact to pull
or inspect, rollback meant reasoning about release directories and
`KEEP_RELEASES`, the server layout lived only on the server, a deploy
"succeeded" when `systemctl restart` exited zero, and the runtime environment
was rewritten by CI from an Actions variable on every run.

Production now runs a private image from the GitHub Container Registry under
docker compose. A green push to `main` builds a multi-stage image, publishes it
as `ghcr.io/zapihq/docs.zapihq.com:sha-<7>` plus a moving `latest`, and the
deploy job syncs the versioned compose file to `/opt/zapi-docs`, pulls the
pinned tag, replaces the container, and verifies `/api/health` before reporting
success. `sha-*` tags are immutable: an existing tag is reused rather than
re-pushed, so the same tag always names the same image. `latest` is a
convenience tag and is never the deployed reference.

The edge stays where it was. Host nginx keeps terminating TLS with the wildcard
certificate, keeps enforcing the Basic Auth gate, and keeps proxying
`docs.zapihq.com` to `127.0.0.1:3002`. The container publishes on loopback only
and runs as the non-root `node` user. Runtime secrets live in the
operator-owned `/opt/zapi-docs/.env` (mode 600); CI never writes it. The
registry credential is the workflow run's short-lived `GITHUB_TOKEN`, staged as
a file for login and removed afterwards, so no long-lived registry credential
sits on the box. The deploy account is not in the `docker` group, which is an
implicit root grant; it gets one sudoers rule for `/usr/bin/docker` instead.

Rollback is a `workflow_dispatch` carrying the previous `sha-*` tag, as long as
that tag is still inside the retention window. It skips checks and publishing,
pulls that tag, and reuses the normal deploy path. A failed pull leaves the
running container alone. If the new container is unhealthy, the deploy restores
the previously running tag and says whether that restore succeeded.

## The server contract

The server has three files, all in `${DEPLOY_PATH}` (default
`/opt/zapi-docs`), named by owner:

| File          | Owner    | Contents                                                      |
| ------------- | -------- | ------------------------------------------------------------- |
| `compose.yml` | CI       | Topology, re-synced from `docker/compose.yml` on every deploy. |
| `.image.env`  | CI       | Deploy state: image tag and host port, no secrets.             |
| `.env`        | Operator | Runtime environment, mode 600, never written by CI.            |

Deploy state is separate for two reasons. CI must not write the runtime
environment: the secrets are hand-managed on the host, and a deploy has no
business rewriting them. And a compose file with a baked tag would no longer
match the versioned file in the repository, so the tag and host port are
interpolated from `.image.env` beside the synced, reviewable `compose.yml`.

## Verification

Deploy health is verified through the nginx upstream on
`http://127.0.0.1:3002/api/health`, from the server itself. The public URL is
Basic Auth gated, so CI does not probe it; a `401` there is the expected edge
behaviour, not a deploy signal. A rollback is verified the same way.

## Runbook scope

`docs/agents/deploy.md` describes only the current container path: normal
deploy, rollback, fresh host, the deploy account's privilege, and failure
triage. The retired cutover and teardown procedure is historical, not a
runbook step; it lives in the appendix below, and the runbook carries one
pointer to it.

## Publishing and `latest`

`latest` moves only when a new immutable tag is built. A same-commit re-run
finds the `sha-*` tag already published, skips the build, and leaves `latest`
where it is. The deployed reference is always the immutable tag.

## Consequences

- "What is production running?" is answered by an image tag, and the image
  records its source revision in the `org.opencontainers.image.revision` label.
- The same image runs on a laptop and on the server, so a local run says
  something about the shipped artifact.
- The production topology is in the repository as `docker/compose.yml`; the
  three-file server contract is described above.
- Deploys are idempotent. Re-running a deploy for the same tag does not rebuild
  the image or recreate the container when nothing changed.
- A failed pull or unhealthy container is a red deploy, not a silent 502. The
  job fails with the stage that failed: configuration, SSH, registry login,
  pull, compose up, or health.
- There is a short gap while the old container is replaced. This is accepted;
  zero-downtime and blue-green are out of scope.
- The first cutover was the only step with a longer outage: systemd owned port
  3002, so the unit had to stop before compose could bind. Later deploys are
  container swaps.
- The deploy still needs SSH credentials. They were deliberately kept when the
  tarball path was retired.
- The image is amd64-only and there is one production environment. There is no
  separate pre-production environment, per-PR preview, or secret manager; the
  server `.env` stays hand-managed.
- Old images are pruned on the server after a successful deploy, and the
  publish job keeps the 20 newest `sha-*` versions plus `latest` in GHCR,
  deleting older `sha-*`-only and unattached versions, so a rollback target
  older than that window is gone unless it also carries a manual tag.

## Rejected alternatives

**Put nginx in the compose stack.** The edge is shared with the apex
`zapihq.com` site and its certificate renewal. Moving nginx into this compose
project would take over ports 80 and 443, TLS configuration, ACME renewal, and
the Basic Auth gate for both sites, and a docs container restart would become
an edge restart. It would also create two owners for one edge while the apex
site stayed outside the repository. The existing nginx already proxies the
right upstream and was proven unchanged at cutover. Containerizing the edge is
a separate change with a separate risk; it is not required to ship the docs
artifact.

**Keep a long-lived registry token on the server.** A PAT or registry password
on the box is a persistent credential that can read, and possibly write, the
private package, and it has to be rotated and audited independently of
deploys. The run-scoped `GITHUB_TOKEN` is available only for the deploy job,
authenticates once, and is removed. The trade-off is deliberate: manual
`docker pull` on the server is not supported, which is why rollback goes
through the workflow rather than an SSH session.

**Deploy the moving `latest` tag.** A moving reference cannot answer what is
running, cannot be used for a deterministic rollback, and makes an idempotent
redeploy ambiguous. The workflow publishes `latest` for convenience only; the
compose file interpolates an immutable `sha-*` tag.

**Stay on the tarball and systemd path.** Keeping the release-directory tree on
the server preserves every problem above: no artifact, rollback by
archaeology, drift that only exists on one machine, no health signal, and a
plaintext runtime environment written by CI.

**Add the deploy account to the `docker` group.** Membership in the `docker`
group is equivalent to root on the host, because Docker can mount the host
filesystem. A single sudoers rule for `/usr/bin/docker` is still root-equivalent
in practice, but it is explicit, auditable, and does not quietly grant every
other docker command to the account.

## Appendix: retired cutover and teardown (historical)

This procedure is kept for the record. It was completed when the container
path replaced the tarball/systemd path and is not part of the current runbook.
Do not replay it on a host that already runs the container.

### Cutover

The initial cutover was the only step with a real outage, because systemd
already owned port 3002. It ran after the image was published and the host had
Docker with the compose plugin, the `deploy_doc` account and key, the sudoers
rule, `/opt/zapi-docs` writable, and `/opt/zapi-docs/.env` mode 600.

1. Confirm the image tag is published and `/opt/zapi-docs` exists and is
   writable by `deploy_doc`. Place `compose.yml` there.
2. Create `/opt/zapi-docs/.env` with the runtime secrets, owned so compose can
   read it and mode 600. If the old shared environment file exists at
   `/var/www/zapi-docs/shared/.env.production`, copy its keys; do not assume the
   new `.env` already has every key. Write `.image.env` with the published tag
   and `PORT=3002`.
3. Make sure the deploy account's sudoers rule is installed, then test it as
   `deploy_doc` with `sudo -n /usr/bin/docker version`.
4. Log in to `ghcr.io` with a short-lived credential and pull the image before
   stopping the old service, so the outage covers only the swap:

   ```bash
   cd /opt/zapi-docs
   sudo docker compose --env-file .image.env pull
   ```

   A pull does not bind the port.

5. Stop and disable the unit: `sudo systemctl stop zapi-docs` and
   `sudo systemctl disable zapi-docs`. Port 3002 is now free. From here until
   the container is healthy, nginx returns `502`; that is expected during the
   swap.
6. Start the container from `/opt/zapi-docs`:

   ```bash
   sudo docker compose --env-file .image.env up --detach --wait
   ```

   Leave the old `/var/www/zapi-docs` tree in place for teardown.
7. Verify the loopback health body, the running image tag, and the external
   `401` with the Basic Auth challenge.

If the container did not become healthy, stop it first so it releases port
3002, then bring the old service back:

```bash
sudo docker compose --env-file .image.env down
sudo systemctl start zapi-docs
```

### Teardown

Teardown was the one-way removal of the retired path, and it ran only after a
container deploy and a rollback had both been proven on the box. It ran as a
root-capable operator, not as `deploy_doc`, because the deploy account's narrow
rule allows only `/usr/bin/docker`.

1. Confirm the container is healthy and a rollback dispatch has succeeded.
2. Before deleting the old environment file, compare key names, not values:

   ```bash
   sudo sed -E 's/=.*/=<redacted>/' /var/www/zapi-docs/shared/.env.production
   sudo sed -E 's/=.*/=<redacted>/' /opt/zapi-docs/.env
   ```

   Copy any key still needed into `/opt/zapi-docs/.env`, keep it mode 600, and
   re-run a deploy.

3. Confirm the old path is not serving:

   ```bash
   systemctl is-active zapi-docs    # inactive
   systemctl is-enabled zapi-docs   # disabled
   ss -lntp | grep ':3002'          # docker-proxy, not a node process
   ```

4. Remove the unit. `systemctl cat zapi-docs` shows the actual unit file;
   remove that file, not a guessed path:

   ```bash
   sudo systemctl stop zapi-docs
   sudo systemctl disable zapi-docs
   sudo rm /etc/systemd/system/zapi-docs.service
   sudo systemctl daemon-reload
   sudo systemctl reset-failed zapi-docs
   ```

5. Remove the old release tree. Check the exact path first, then delete only
   that directory. Do not remove `/var/www` itself:

   ```bash
   sudo ls -la /var/www/zapi-docs
   readlink -f /var/www/zapi-docs/current
   sudo rm -rf /var/www/zapi-docs
   ```

6. Remove GitHub configuration that belonged to the retired path, from the
   `production` environment: variables `SERVICE_NAME`, `KEEP_RELEASES`, and
   `OPENROUTER_API_KEY`; secret `RUNTIME_ENV_FILE`. Keep `DEPLOY_PATH`,
   `SSH_HOST`, `SSH_PORT`, `SSH_USER`, `SSH_PRIVATE_KEY`, and
   `SSH_KNOWN_HOSTS`; keep `NEXT_PUBLIC_SITE_URL`. `PORT` is optional and
   defaults to 3002.

7. Prove nothing needed the deleted state: dispatch a deploy for the live tag
   and confirm the live tag, loopback health, the public `401`, and
   `sudo nginx -t`.
