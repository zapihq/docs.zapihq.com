# Deploying docs.zapihq.com

Production is a private container image running under docker compose on the
server, behind the existing host nginx. CI is the only deploy path. This page
is the runbook for a normal deploy, a rollback, a fresh host, the deploy
account's privilege, and failure triage. The decision behind it is in
`docs/adr/0003-docker-ghcr-over-tarball-systemd.md`; the retired cutover and
teardown procedure is historical and lives in that ADR's appendix.

## What is running

| Piece           | Where it lives                                                                                                                                                                                                                                                           |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Edge            | Host nginx. Terminates TLS with the wildcard certificate, enforces the Basic Auth gate, and proxies `docs.zapihq.com` to `127.0.0.1:3002`. Its configuration and certificate renewal are unchanged by this deploy.                                                       |
| Application     | Container `zapi-docs`, from the private image `ghcr.io/zapihq/docs.zapihq.com:<tag>`. It listens on 3000 in the container, publishes only on loopback `127.0.0.1:3002`, runs as the non-root `node` user, restarts unless stopped, and caps json-file logs at 10 MB × 3. |
| Compose file    | `/opt/zapi-docs/compose.yml`, CI-owned topology. CI overwrites it on every deploy from `docker/compose.yml`.                                                                                                                                                              |
| Deploy state    | `/opt/zapi-docs/.image.env`, CI-written on every deploy. It carries the image tag and host port (`IMAGE_TAG`, `PORT`), no secrets.                                                                                                                                       |
| Runtime env     | `/opt/zapi-docs/.env`, operator-owned, mode 600. CI never writes it; it is the only place the runtime secrets live on the server.                                                                                                                                         |
| Registry        | Private GHCR package. `sha-<7>` tags are immutable; `latest` is a moving convenience tag and is never the deployed reference. Retention is described under [Normal deploy](#normal-deploy).                                                                              |
| Deploy account  | `deploy_doc`, home `/home/deploy_doc`, with one narrow sudoers rule for `/usr/bin/docker`; not a member of the `docker` group.                                                                                                                                           |
| Workflow        | `.github/workflows/deploy.yml`, calling `ci.yml` and `publish.yml` on a normal deploy.                                                                                                                                                                                   |

The site is Basic Auth gated at nginx. `curl -I https://docs.zapihq.com`
returning `401` with `WWW-Authenticate: Basic` is normal. The real health check
is the loopback endpoint.

## Normal deploy

Merge to `main`, or run the **Deploy** workflow with `image_tag` empty:

```bash
gh workflow run deploy.yml
```

On a push to `main`, the pipeline is: checks → publish image → deploy. A
dispatch with no tag runs the same three jobs on the selected commit. The
publish job builds `sha-<7>` plus `latest` only when the immutable tag does not
already exist, then prunes GHCR versions beyond the newest 20 `sha-*` versions,
keeping `latest`. Only versions whose every tag is `sha-*` are deleted; a
version with a manual tag is left alone. Untagged versions older than the
oldest kept image are deleted too, so the attestation manifests buildx attaches
to a pruned image do not pile up. The prune is best-effort: if the registry
rejects it, that step goes red but the deploy still runs. `latest` moves only
when a new immutable tag is built; re-running the workflow for the same commit
skips the build and leaves `latest` where it is.

The deploy job runs these steps:

1. **Resolve image tag** — resolves the tag and validates it against Docker's
   tag grammar.
2. **Validate deploy configuration** — checks `IMAGE_TAG`, `IMAGE_REPOSITORY`,
   `DEPLOY_PATH`, `SSH_HOST`, `SSH_PORT`, `SSH_USER`, `PORT`,
   `SSH_PRIVATE_KEY`, and `SSH_KNOWN_HOSTS` before any SSH call. `PORT` is
   defaulted to 3002 by the workflow, so the operator does not set it unless
   nginx uses another port.
3. **Prepare SSH credentials** — writes the deploy key and the known-hosts
   file.
4. **Sync compose file** — copies `docker/compose.yml` to
   `/opt/zapi-docs/compose.yml`. CI never touches the `.env` beside it.
5. **Stage registry token** — copies the run's short-lived `GITHUB_TOKEN` to
   `${DEPLOY_PATH}/.ghcr-token` so it never appears in a process list. This
   step does not log in to the registry.
6. **Pull, replace, verify, prune** — logs in to `ghcr.io` with the staged
   token, records the tag of the container that is currently running, writes
   `.image.env`, pulls the pinned tag, and runs
   `docker compose up --detach --wait --wait-timeout 90`. It checks that the
   running container's image is the requested tag and that
   `GET http://127.0.0.1:3002/api/health` returns `{"status":"ok"}`, prunes
   images carrying this repository's source label that are older than 168
   hours, logs out, and prints `Live tag: <tag>`.
7. **Report the live tag** — writes the **Live tag** notice and the run
   summary.

A cancelled or failed run still runs **Remove staged registry token** last. It
removes only `${DEPLOY_PATH}/.ghcr-token` over SSH and warns instead of failing
when the host is unreachable, so it cannot replace the real failure and cannot
touch `.env`, `compose.yml`, or `.image.env`.

A successful run ends with `Live tag: sha-…` in the log and a **Live tag**
notice on the run. There is no manual pull or restart step. Re-running the same
tag is idempotent: publishing skips the existing image and compose does not
recreate an unchanged container.

Verify a deploy from the server's loopback, not the public URL:

```bash
ssh deploy_doc@<host> 'curl -sS http://127.0.0.1:3002/api/health'
# {"status":"ok"}

ssh deploy_doc@<host> \
  'sudo -n /usr/bin/docker ps --filter name=zapi-docs --format "{{.Image}}  {{.Status}}"'
# ghcr.io/zapihq/docs.zapihq.com:sha-…  Up … (healthy)
```

## Rollback

Roll back by dispatching the same **Deploy** workflow with the previous
`sha-<7>` tag. Do not SSH in and pull by hand; the server has no long-lived
registry credential.

```bash
gh workflow run deploy.yml -f image_tag=sha-1a2b3c4
```

A dispatch carrying a tag skips checks and publishing and goes straight to the
deploy job. It follows the normal pull, replace, and health path, so the run log
and summary still report the live tag. Find the previous tag in the notice of an
earlier successful run, or in the package's version list in GitHub. Only the
newest 20 `sha-*` versions are kept, so a target older than that window has
been deleted unless it also carries a manual tag.

What the failure modes mean:

- **Pull fails** (`tag is not published` or `the tag is missing or the token
cannot read it`): the running container is untouched and `.image.env` is put
  back to the tag that was already live.
- **New container unhealthy**: the job prints the last 100 log lines and tries
  to restore the previously running tag. The failure says whether the restore
  succeeded, or why it could not restore.
- **Health body is not `{"status":"ok"}`**: treat it as an unhealthy deploy;
  the restore path above applies.

Rollback changes production, not `main`. `latest` also stays where it was,
because no image is published during a rollback. Fix or revert the bad commit
on `main`, then let the next push deploy normally. A later push will otherwise
deploy the unfixed code again.

## A fresh host

A rebuilt host starts from a clean Ubuntu server; there is no older deploy
layout to migrate. Do the host setup once, as root:

1. Install Docker with the compose plugin, plus `curl`. The deploy's health
   probe runs `curl` on the host, so a rebuilt host without it fails at the
   last step.
2. Create the deploy account and install the public half of the deploy key:

   ```bash
   useradd --create-home --shell /bin/bash deploy_doc
   install -d -m 700 -o deploy_doc -g deploy_doc /home/deploy_doc/.ssh
   # Write the public key to /home/deploy_doc/.ssh/authorized_keys,
   # owned by deploy_doc and mode 600.
   ```

3. Create `/opt/zapi-docs` and give `deploy_doc` write access. CI re-syncs
   `compose.yml` into it and writes `.image.env` beside it on every deploy.
4. Create `/opt/zapi-docs/.env` with the runtime secrets, owned so compose can
   read it and mode 600; CI never writes it.
5. Install the sudoers rule below and point nginx's `docs.zapihq.com` block at
   `127.0.0.1:3002`. Leave the Basic Auth gate and wildcard certificate at the
   edge.
6. In the `production` environment, set `DEPLOY_PATH=/opt/zapi-docs`, plus
   `SSH_HOST`, `SSH_PORT`, `SSH_USER`, `SSH_PRIVATE_KEY`, and
   `SSH_KNOWN_HOSTS`. `PORT` is optional and defaults to 3002; set it only
   when nginx proxies to a different port.

Then run the **Deploy** workflow as in [Normal deploy](#normal-deploy). It
writes `compose.yml` and `.image.env` to `/opt/zapi-docs`, pulls the image,
starts the container, and verifies health.

## The deploy account's privilege

The deploy account is `deploy_doc`. It gets one sudoers entry in
`/etc/sudoers.d/zapi-docs-deploy`:

```sudoers
deploy_doc ALL=(ALL) NOPASSWD: /usr/bin/docker
```

The file must be mode 0440 and valid according to `visudo -cf`. Test it as the
deploy account:

```bash
sudo -n /usr/bin/docker version
```

Do not add `deploy_doc` to the `docker` group. That group can mount the host
filesystem and is an implicit root grant. The single-binary rule is still
root-equivalent in practice, because Docker can be asked to mount host paths,
so treat the deploy SSH key with the same care as a root key. The rule is
narrow because it names one command and is auditable, not because Docker is
unprivileged.

`deploy_doc`'s home is `/home/deploy_doc`; its `.ssh/authorized_keys` holds the
deploy key. Do not move the home under a deploy path or delete it during host
cleanup: losing it locks CI out of the server.

`deploy_doc` also needs to write `/opt/zapi-docs/compose.yml`, `.image.env`, and
the short-lived token file, and it must be able to read `.env` through compose.
There is no broader session for this account: the deploy path uses only this
rule.

## When a deploy fails

The workflow fails at a named stage. Start there before reading the stack.

| Stage                           | What to check                                                                                                                                                                                                                                                                                                                                                             |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Checks or publish               | No deploy ran. Fix the commit; a red check must never reach production.                                                                                                                                                                                                                                                                                                   |
| Validate deploy configuration   | The `production` environment is missing a variable or secret. Required: `DEPLOY_PATH`, `SSH_HOST`, `SSH_PORT`, `SSH_USER`, `SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`. `PORT` is optional and defaults to 3002. `GITHUB_TOKEN` is automatic.                                                                                                                                      |
| Prepare SSH credentials / Sync compose file | Host, port, user, key, and known-hosts. Confirm the deploy key still authenticates as `deploy_doc`, that port 22 is reachable, that `/opt/zapi-docs` is writable, and that `/home/deploy_doc/.ssh/authorized_keys` holds the deploy key.                                                                                                                                  |
| Pull, replace, verify, prune    | The registry login and pull happen here. `image_tag` is a Docker tag, not a digest or branch. `not published` means the tag does not exist; `missing or the token cannot read it` deliberately covers both a missing tag and an unreadable private package. The running container is left alone.                                                                             |
| Prune old package versions      | The red step does not block the deploy. `::warning::Could not delete package version …` means the REST delete failed; a later publish that builds a new version retries it. If every publish goes red here, confirm the job still has `packages: write` and that the GHCR package is still linked to this repository.                                                     |
| Missing `.env` or mode          | `/opt/zapi-docs/.env` must exist and be mode 600. Fix ownership and mode. Never let CI write it.                                                                                                                                                                                                                                                                          |
| `deploy user cannot run docker` | The sudoers rule is missing or wrong. Install it as root and test `sudo -n /usr/bin/docker version`.                                                                                                                                                                                                                                                                      |
| Compose up or unhealthy         | Read the job's last 100 container lines, then reproduce with `cd /opt/zapi-docs && sudo -n /usr/bin/docker compose --env-file .image.env logs --tail 100 app`. Check the image health status, the env keys, and whether something else owns 3002. The job attempts to restore the previous tag; if it says the restore failed, dispatch a rollback for the last good tag. |
| Health body mismatch            | Check `curl -sS http://127.0.0.1:3002/api/health`, `docker inspect --format '{{.State.Health.Status}}' zapi-docs`, and the image tag that is actually running. nginx is not in this path.                                                                                                                                                                                 |
| Deploy green but public `502`   | The app is healthy but the host edge is not reaching it. Check the listener on 3002 with `ss -lntp`, the nginx upstream, `sudo nginx -t`, and nginx's error log. Do not restart nginx unless a config change requires it; the certificate renewal path is outside this deploy.                                                                                            |
| Deploy green but public `401`   | Expected. The Basic Auth gate is at nginx. The deploy verifies loopback health, not the gated public response.                                                                                                                                                                                                                                                            |
| Run cancelled or queued         | The `production-deploy` concurrency group never cancels a deploy in progress. Let the running one finish, then re-run or dispatch the tag you want. A failed or cancelled run still attempts to remove the staged token; if that step warns, delete `/opt/zapi-docs/.ghcr-token` by hand.                                                                                  |

Useful read-only commands:

```bash
ssh deploy_doc@<host> 'sudo -n /usr/bin/docker inspect --format "{{.Config.Image}} {{.State.Health.Status}}" zapi-docs'
ssh deploy_doc@<host> 'cd /opt/zapi-docs && sudo -n /usr/bin/docker compose --env-file .image.env ps'
ssh deploy_doc@<host> 'curl -sS http://127.0.0.1:3002/api/health'
gh run list --workflow=deploy.yml --limit 5
```

If a bad image is already live, roll back first and diagnose afterwards. Do not
try to fix production by editing `.image.env`: the next deploy overwrites it.
