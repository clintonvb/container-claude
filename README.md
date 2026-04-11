# container-claude

Headless [Claude Code](https://claude.com/claude-code) running in Docker, driven
remotely from claude.ai/code. No web terminal exposed, no inbound ports, auto-updating
nightly via GitHub Actions and Watchtower.

## What this is

A minimal Dockerfile that installs the official Claude Code CLI on top of
`node:22-bookworm-slim`, plus a compose file to run it and a GitHub Actions workflow
that rebuilds the image whenever a new Claude Code CLI version is published to npm,
plus a weekly rebuild to pick up base-image security patches.

You interact with the container from your laptop or phone through Claude Code's
Remote Control feature: the container makes outbound connections to Anthropic's API
and appears as a session in the sidebar at claude.ai/code. You send commands from
there. Nothing on the host listens on a port.

## Architecture

```
  this repo
       |
       | git push, daily version check, weekly rebuild
       v
  GitHub Actions
    check npm for new @anthropic-ai/claude-code
    build --pull --no-cache if newer
    push -> ghcr.io/<owner>/container-claude:{latest, X.Y.Z, X.Y.Z-YYYYMMDD}
       |
       | watchtower polls daily
       v
  Docker host
    claude container  ---- outbound HTTPS ---->  api.anthropic.com
                                                       ^
                                                       |
                                                  claude.ai/code
                                                  (laptop / phone)
```

## Prerequisites

- A Docker host with `docker compose` (any Linux box, NAS, or VPS)
- A GitHub account
- An Anthropic account with Claude Code access
- Outbound HTTPS from the host to `api.anthropic.com` and `ghcr.io`

## Repository layout

```
container-claude/
├── Dockerfile
├── compose.yaml
├── .github/
│   └── workflows/
│       └── build.yml
├── .gitignore
└── README.md
```

## Setup

### 1. Fork or clone this repo

Push the files to your own repo. The workflow runs on push; wait for it to turn
green under the Actions tab, then confirm the package at Profile → Packages →
`container-claude` exists.

### 2. Prepare the host folders

```bash
mkdir -p <host-data-path> <host-workspace-path> <host-npm-global-path>
chown -R <UID>:<GID> <host-data-path> <host-workspace-path> <host-npm-global-path>
```

The UID/GID must match the `user:` line in `compose.yaml`.

### 3. OAuth bootstrap (one-off)

Claude Code needs to be logged in once before Remote Control can run. Use a throwaway
container that reuses the compose service definition, so credentials land on the
right bind mount as the right user:

```bash
docker compose run --rm claude claude
```

Follow the device-code login flow: open the printed URL on your laptop, sign into
Anthropic, approve the device. `/exit` or Ctrl-C to leave. Credentials are now
written to the data bind mount and will persist across restarts and image upgrades.

### 4. Start the stack

```bash
docker compose up -d
```

The container starts `claude --remote-control` using the credentials from step 3.

### 5. Drive it from claude.ai/code

1. Go to https://claude.ai/code on your laptop or phone.
2. Sign in with the same Anthropic account as the bootstrap.
3. The container's session appears in the sidebar with a green status dot.
4. Click it and send commands. File reads/writes go to the workspace bind mount.

## Updating

Nothing to do. The pipeline handles it:

- **Daily 03:00 UTC**: GitHub Actions checks npm for a new `@anthropic-ai/claude-code`
  release. If there is one, it builds the image pinned to that exact version and
  pushes to GHCR. If the current version is already built, nothing happens — no
  wasted build minutes.
- **Weekly Sunday 04:00 UTC**: Forces a rebuild regardless, so Debian/Node base image
  security patches land even if Claude Code hasn't changed.
- **Daily**: Watchtower on the host pulls the new image, recreates the container,
  and cleans up the old image.

Credentials, memory, MCP configs, and the workspace survive because they're on bind
mounts. The Remote Control session reconnects automatically.

Force an update now:

```bash
# trigger a rebuild: GitHub repo -> Actions -> build -> Run workflow
# then on the host:
docker compose pull && docker compose up -d
```

### Image tags

Every successful build pushes three tags:

| Tag | Example | Meaning |
|---|---|---|
| `latest` | `latest` | Always points at the newest build. Use this for hands-off auto-update. |
| `X.Y.Z` | `2.1.14` | The Claude Code CLI version installed inside the image. |
| `X.Y.Z-YYYYMMDD` | `2.1.14-20260411` | Specific build day. Use for precise rollback if a base-image rebuild introduces a regression. |

To pin a specific version in `compose.yaml`, change the `image:` line from `:latest`
to `:2.1.14` (or whichever). Watchtower will stop auto-updating that container —
intentional if you want the pin to hold.

## Security notes

- **No inbound ports.** The container has no published ports. Verify with
  `docker port claude` — it should return nothing.
- **Isolated network.** `claude-net` is a dedicated bridge with no route to other
  services on the host.
- **Non-root, dropped caps, read-only FS.** Any write has to go through a declared
  bind mount or tmpfs, so unexpected writes are visible on the host.
- **OAuth credentials are sensitive.** Whoever has the `.claude` folder can act as
  your Anthropic account. Back it up somewhere encrypted if the backup leaves the
  host. Do not commit it.
- **Revocation.** If something looks wrong: claude.ai → Settings → revoke the
  device/session. The container's Remote Control connection dies immediately. Wipe
  the credentials folder, redeploy, re-bootstrap.
- **Consider a separate Anthropic account** if this container will run untrusted
  code. Stolen OAuth tokens give full access to whichever account they belong to.

## Cost

Zero on a public repo:

| Component | Cost |
|-----------|------|
| GitHub Actions (public repo) | Free, unlimited minutes |
| GHCR storage + pulls (public image) | Free, unlimited |
| Watchtower | Free, runs on your host |
| Anthropic subscription | Whatever you already pay |

Private repo: 2,000 free Actions minutes/month (a nightly ~3-minute build uses ~90),
500 MB free GHCR storage. Still effectively zero.

## Troubleshooting

**`docker compose run --rm claude claude` fails with a permission error**
The bind mount folders aren't owned by the UID inside the container. Re-run the
`chown` in step 2 with the UID/GID that matches the `user:` line in `compose.yaml`.

**Container exits immediately after `up -d`**
`docker logs claude` — if it complains about missing credentials, the OAuth bootstrap
(step 3) didn't land in the bind mount. Verify the data folder contains files owned
by the right UID.

**`npm install` layer fails during build**
Transient registry or GHCR issue. Re-run the workflow.

**Session doesn't appear at claude.ai/code**
- `docker logs claude` — look for connection errors or expired token messages.
- Confirm outbound network: `docker exec claude curl -sI https://api.anthropic.com`
  should return a 200 or 401 (either proves connectivity).
- Re-run the OAuth bootstrap if the token was revoked.

**Watchtower isn't updating the container**
`docker logs watchtower` shows its check cycle. If it's running but not updating,
try `docker compose pull` manually to confirm GHCR has a newer digest than what's
running.

**I edited the Dockerfile but the host still has the old image**
Push triggers a rebuild, but Watchtower only polls once per day. Wait or force an
update with the steps above.

## License

See [LICENSE](LICENSE).
