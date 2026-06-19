# Deployment guide

Install Matrix on a fresh Linux host. After this you'll have every container
running; the per-service **first-run** clicks are in the [User guide](user-guide.md).

## Prerequisites

- A Linux host (tested on Debian/Ubuntu). A regular login user with `sudo`.
- Outbound internet (to pull images and install Docker).
- Disk: whatever you'll give Plex, plus a few GB for configs and 15 days of
  Prometheus history. Ideally a **second disk/path** for backups.
- Ports free on the host: `53`, `80`, `81`, `443`, `784`, `853`, `3000`, `3001`,
  `5055`, `6767`, `7878`, `8082`, `8083`, `8090`, `8989`, `9000`, `9090`, `9091`,
  `9696`, `51413`, plus Plex's `32400`. If `systemd-resolved` holds `:53`,
  `setup.sh` warns you and prints the fix.

## One-command bootstrap

```bash
git clone https://github.com/tomibernardin/matrix.git && cd matrix
./setup.sh
```

`setup.sh` auto-elevates with `sudo`. It is **idempotent** — safe to re-run any
time (after a `git pull`, for instance). In one pass it:

1. Installs OS utilities, Docker Engine and the compose plugin (skips Docker if
   already present).
2. Adds your user to the `docker` group and resolves the docker group GID.
3. Generates `.env` from `.env.example` with detected values
   (`PUID`/`PGID` from your user, `TZ` from the host, paths under `${HOME}/docker`)
   and **random** secrets for `TRANSMISSION_PASS` and `GRAFANA_ADMIN_PASSWORD`.
   `.env` is written mode `600`, owned by you. *If `.env` already exists it is
   left untouched.*
4. Creates the directory tree under `DOCKER_MAIN_ROUTE`.
5. Seeds the FileBrowser file-stubs and copies the repo-owned Prometheus +
   Grafana configs into the tree.
6. Applies ownership/permissions (you, plus Grafana→472 / Prometheus→65534).
7. Installs the nightly backup cron job (`/etc/cron.d/matrix-backup`, 05:30).

> **Running as root?** If you must, the script can't read `$SUDO_USER`. Pass the
> target user explicitly: `MATRIX_USER=alice bash setup.sh`. Note `sudo`'s env
> sanitization strips it, so use that exact form (not `sudo MATRIX_USER=… ./setup.sh`).

## Pick up docker group membership

The `docker` group was just added to your user but your current shell predates
it. Either log out and back in, or:

```bash
newgrp docker
```

## Add your Plex claim token (optional but recommended)

Plex needs a one-time claim token to bind the server to your account on first
start. It's valid ~4 minutes, so get it right before bringing the stack up:

1. Open <https://www.plex.tv/claim/> while signed in to Plex.
2. Copy the `claim-xxxx` token.
3. Put it in `.env`:
   ```bash
   $EDITOR .env      # set PLEX_CLAIM=claim-xxxxxxxxxxxx
   ```

If you skip this you can still claim the server later from the Plex web UI.

## Bring the stack up

```bash
docker compose up -d
docker compose ps
```

Give it a minute, then re-check `docker compose ps`. Every service should report
`healthy` **except**:

- **Plex** — has no healthcheck; check `http://<host>:32400/web`.
- **AdGuard** — reports healthy only after you finish its setup wizard.
- **node-exporter** — has no healthcheck by design (Prometheus's scrape is the
  liveness signal).

## Next

Now do the [User guide](user-guide.md) once — it walks every service's first-run
setup, the reverse-proxy wiring, Prowlarr indexers and the Homepage widget keys.

## Updating an existing deployment

When you pull new repo changes onto a host that's already running:

```bash
git pull
./setup.sh                              # re-syncs repo-owned configs + cron (idempotent)
docker compose up -d --remove-orphans   # --remove-orphans retires removed services
```

`--remove-orphans` matters after PRs that drop a service (e.g. Jackett → Prowlarr):
it removes the old container. Old **data** directories are left on disk on
purpose — delete them by hand when you're sure.
