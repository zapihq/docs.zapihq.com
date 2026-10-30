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

Rollback is a `workflow_dispatch` carrying the previous `sha-*` tag. It skips
checks and publishing, pulls that tag, and reuses the normal deploy path. A
failed pull leaves the running container alone. If the new container is
unhealthy, the deploy restores the previously running tag and says whether that
restore succeeded.

## Consequences

- "What is production running?" is answered by an image tag, and the image
  records its source revision in the `org.opencontainers.image.revision` label.
- The same image runs on a laptop and on the server, so a local run says
  something about the shipped artifact.
- The production topology is in the repository as `docker/compose.yml`. The
  server has three files: CI-owned `compose.yml`, CI-written `.image.env`
  (tag and host port, no secrets), and operator-owned `.env`.
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
- Old images are pruned on the server after a successful deploy. Registry tag
  cleanup is not automated in this repository, so a rollback target must still
  exist in GHCR.

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
