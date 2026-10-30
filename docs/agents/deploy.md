# Deploying docs.zapihq.com

Production is a private container image running under docker compose on the
server, behind the existing host nginx. CI is the only deploy path. This page
is the runbook for a normal deploy, a rollback, a fresh host, and failure
triage. The decision behind it is in
`docs/adr/0003-docker-ghcr-over-tarball-systemd.md`.

## What is running

| Piece           | Where it lives                                                                                                                                                                                                                                                           |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Edge            | Host nginx. Terminates TLS with the wildcard certificate, enforces the Basic Auth gate, and proxies `docs.zapihq.com` to `127.0.0.1:3002`. Its configuration and certificate renewal are unchanged by this deploy.                                                       |
| Application     | Container `zapi-docs`, from the private image `ghcr.io/zapihq/docs.zapihq.com:<tag>`. It listens on 3000 in the container, publishes only on loopback `127.0.0.1:3002`, runs as the non-root `node` user, restarts unless stopped, and caps json-file logs at 10 MB × 3. |
| Compose file    | `/opt/zapi-docs/compose.yml`. CI owns it and overwrites it on every deploy.                                                                                                                                                                                              |
| Image variables | `/opt/zapi-docs/.image.env`, written by CI on every deploy. It carries `IMAGE_TAG` and `PORT`, no secrets.                                                                                                                                                               |
| Runtime secrets | `/opt/zapi-docs/.env`, operator-owned, mode 600. CI never writes it.                                                                                                                                                                                                     |
| Registry        | Private GHCR package. `sha-<7>` tags are immutable; `latest` is a moving convenience tag and is never the deployed reference.                                                                                                                                            |
| Deploy account  | `deploy_doc`, home `/home/deploy_doc`, with one narrow sudoers rule for `/usr/bin/docker`; not a member of the `docker` group. The home holds the deploy key in `.ssh/authorized_keys`.                                                                                  |
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
already exist. The deploy job then:

1. Resolves the tag, validates it against Docker's tag grammar, and checks the
   required environment variables and secrets.
2. Copies `docker/compose.yml` to `/opt/zapi-docs/compose.yml`. CI never
   touches the `.env` beside it.
3. Stages the run's short-lived `GITHUB_TOKEN` as a file, logs in to `ghcr.io`,
   and records the tag of the container that is currently running.
4. Writes `.image.env`, pulls the pinned tag, and runs
   `docker compose up --detach --wait --wait-timeout 90`.
5. Checks that the running container's image is the requested tag and that
   `GET http://127.0.0.1:3002/api/health` returns `{"status":"ok"}`.
6. Prunes images carrying this repository's source label that are older than
   168 hours, logs out, and prints `Live tag: <tag>`.

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
earlier successful run, or in the package's version list in GitHub.

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
layout to migrate. Install Docker with the compose plugin, create
`/opt/zapi-docs`, and make it writable by `deploy_doc`. Create
`/opt/zapi-docs/.env` with the runtime secrets, owned so compose can read it
and mode 600; CI never writes it. Install the sudoers rule below, and point
nginx's `docs.zapihq.com` block at `127.0.0.1:3002`. Leave the Basic Auth gate
and wildcard certificate at the edge.

The deploy account's home is `/home/deploy_doc`; its `.ssh/authorized_keys`
holds the deploy key. Treat the home as credential state, not as part of a
deploy directory.

Then run the **Deploy** workflow:

```bash
gh workflow run deploy.yml
```

It writes `compose.yml` and `.image.env` to `/opt/zapi-docs`, pulls the image,
starts the container, and verifies health. The rest of the runbook is the same
as a normal deploy.

## The deploy account's privilege

The deploy account is `deploy_doc`. It gets one sudoers entry in
`/etc/sudoers.d/zapi-docs-deploy`:

```sudoers
deploy_doc ALL=(root) NOPASSWD: /usr/bin/docker
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
| Validate deploy configuration   | The `production` environment is missing a variable or secret. Required: `DEPLOY_PATH`, `SSH_HOST`, `SSH_PORT`, `SSH_USER`, `PORT`, `SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`. `GITHUB_TOKEN` is automatic.                                                                                                                                                                     |
| SSH or sync compose             | Host, port, user, key, and known-hosts. Confirm the deploy key still authenticates as `deploy_doc`, that port 22 is reachable, that `/opt/zapi-docs` is writable, and that `/home/deploy_doc/.ssh/authorized_keys` holds the deploy key.                                                                                                                                  |
| Registry login or pull          | `image_tag` is a Docker tag, not a digest or branch. `not published` means the tag does not exist; `missing or the token cannot read it` deliberately covers both a missing tag and an unreadable private package. The running container is left alone.                                                                                                                   |
| Missing `.env` or mode          | `/opt/zapi-docs/.env` must exist and be mode 600. Fix ownership and mode. Never let CI write it.                                                                                                                                                                                                                                                                          |
| `deploy user cannot run docker` | The sudoers rule is missing or wrong. Install it as root and test `sudo -n /usr/bin/docker version`.                                                                                                                                                                                                                                                                      |
| Compose up or unhealthy         | Read the job's last 100 container lines, then reproduce with `cd /opt/zapi-docs && sudo -n /usr/bin/docker compose --env-file .image.env logs --tail 100 app`. Check the image health status, the env keys, and whether something else owns 3002. The job attempts to restore the previous tag; if it says the restore failed, dispatch a rollback for the last good tag. |
| Health body mismatch            | Check `curl -sS http://127.0.0.1:3002/api/health`, `docker inspect --format '{{.State.Health.Status}}' zapi-docs`, and the image tag that is actually running. nginx is not in this path.                                                                                                                                                                                 |
| Deploy green but public `502`   | The app is healthy but the host edge is not reaching it. Check the listener on 3002 with `ss -lntp`, the nginx upstream, `sudo nginx -t`, and nginx's error log. Do not restart nginx unless a config change requires it; the certificate renewal path is outside this deploy.                                                                                            |
| Deploy green but public `401`   | Expected. The Basic Auth gate is at nginx. The deploy verifies loopback health, not the gated public response.                                                                                                                                                                                                                                                            |
| Run cancelled or queued         | The `production-deploy` concurrency group never cancels a deploy in progress. Let the running one finish, then re-run or dispatch the tag you want.                                                                                                                                                                                                                       |

Useful read-only commands:

```bash
ssh deploy_doc@<host> 'sudo -n /usr/bin/docker inspect --format "{{.Config.Image}} {{.State.Health.Status}}" zapi-docs'
ssh deploy_doc@<host> 'cd /opt/zapi-docs && sudo -n /usr/bin/docker compose --env-file .image.env ps'
ssh deploy_doc@<host> 'curl -sS http://127.0.0.1:3002/api/health'
gh run list --workflow=deploy.yml --limit 5
```

If a bad image is already live, roll back first and diagnose afterwards. Do not
try to fix production by editing `.image.env`: the next deploy overwrites it.
