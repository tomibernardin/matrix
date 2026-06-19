# Operations runbook

Day-2 tasks for a running Matrix stack: status, logs, updates, backups, restore,
and troubleshooting. Run everything from the repo directory (where `compose.yml`
lives).

## Status & logs

```bash
docker compose ps                    # status + health of every service
docker compose logs -f <service>     # follow one service's logs
docker compose logs --since 1h       # everything in the last hour
docker stats                         # live CPU/mem (also visible in Grafana)
docker compose config --quiet        # validate compose.yml after editing
```

## Start / stop / restart

```bash
docker compose up -d                       # start (or apply changes)
docker compose up -d --remove-orphans      # + retire containers for removed services
docker compose restart <service>           # restart one
docker compose stop                        # stop all (containers kept)
docker compose down                        # stop + remove containers (data tree untouched)
```

## Updating images

Two tracks by design (see [architecture](architecture.md#image-versioning--updates)).

### Auto-updated services (`:latest` + Watchtower)

Most services carry `com.centurylinklabs.watchtower.enable=true`. Watchtower
pulls and recreates them **daily at 04:00**, then cleans old images. Nothing to
do. To update them on demand:

```bash
docker compose pull && docker compose up -d
```

### Pinned services (manual)

Plex, AdGuard, Prometheus and Grafana are pinned to exact tags and are **not**
touched by Watchtower. To upgrade one, bump its tag and pull just it:

```bash
$EDITOR compose.yml      # e.g. grafana/grafana:13.0.2 → 13.1.0
docker compose pull grafana && docker compose up -d grafana
```

Find the latest tag from each project's releases: Plex `linuxserver/docker-plex`,
AdGuard `AdguardTeam/AdGuardHome`, Prometheus `prometheus/prometheus`, Grafana
`grafana/grafana` (Grafana's Docker tag has **no** `v` prefix).

## Backup & restore

### How backups work

`setup.sh` installed `/etc/cron.d/matrix-backup`, which runs
[`backup.sh`](../backup.sh) nightly at **05:30**. Each run:

1. Stops the stack (~1 min downtime).
2. Tars `${DOCKER_MAIN_ROUTE}` into `${BACKUP_DIR}/matrix-<STAMP>.tar.gz`,
   **excluding** Plex media, Plex transcode temp, Transmission downloads and the
   Prometheus TSDB (all recoverable/regenerable).
3. Copies `.env` to `${BACKUP_DIR}/env-<STAMP>` (it holds the paths + secrets
   that make the archive restorable).
4. Restarts the stack and prunes to the newest **14** archives.

Run one on demand:

```bash
sudo ./backup.sh
```

Check it's scheduled / view its log:

```bash
cat /etc/cron.d/matrix-backup
tail -f /var/log/matrix-backup.log
```

> Keep `${BACKUP_DIR}` on a **different disk** than `${DOCKER_MAIN_ROUTE}`. A
> backup on the same failing disk isn't a backup. Even better: also copy
> archives off-box (rsync/rclone to another machine or cloud).

### Restore (tested runbook)

On a fresh host, or to recover a broken tree:

```bash
# 1. Clone and bootstrap (installs Docker, creates the tree, sets permissions).
git clone https://github.com/tomibernardin/matrix.git && cd matrix
./setup.sh

# 2. Stop the (empty) stack if it auto-started.
docker compose stop

# 3. Restore the .env snapshot — paths + secrets travel with the backup.
install -m 600 /path/to/backups/env-<STAMP> .env

# 4. Unpack the archive over the data tree (basename comes from .env, e.g. docker/).
source .env
sudo tar -xzf /path/to/backups/matrix-<STAMP>.tar.gz -C "$(dirname "$DOCKER_MAIN_ROUTE")"

# 5. Re-apply ownership/permissions (idempotent; won't touch restored .env/data).
./setup.sh

# 6. Bring it up.
docker compose up -d && docker compose ps
```

Expected: every service finds its old state — *arr libraries, NPM proxy hosts +
certs, AdGuard config, Grafana dashboards. **Plex media is not in the archive**;
re-point or re-copy media into `${PLEX_MEDIA}` (library metadata survives in
`plex/config`).

## Editing repo-owned configs

`prometheus/prometheus.yml`, `prometheus/rules.yml` and
`grafana/provisioning/**` live in the repo and are copied into the data tree by
`setup.sh` on every run. To change them:

```bash
$EDITOR prometheus/rules.yml      # edit in the repo
./setup.sh                        # re-sync into the tree (idempotent)
docker compose up -d prometheus   # or restart the affected service
```

Editing the copies under `${DOCKER_MAIN_ROUTE}` directly will be **overwritten**
on the next `setup.sh` run — always edit in the repo.

## Observability checks

- **Targets up?** Prometheus → `http://<host>:9090/targets` — `prometheus`,
  `cadvisor`, `node` should all be `UP`.
- **Alerts:** `http://<host>:9090/alerts` — disk <15%, memory <10%, container
  gone >5m. They're visible only (no Alertmanager/notifications yet).
- **Dashboards:** Grafana `http://<host>:3001`, login `admin` /
  `GRAFANA_ADMIN_PASSWORD`. The Docker/cAdvisor dashboard is pre-provisioned.

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| A service is `unhealthy` in `docker compose ps` | `docker compose logs <svc>`. Often a bad bind-mount path or a config it can't write — re-run `./setup.sh` to fix perms. |
| AdGuard won't start, `:53` in use | `systemd-resolved` holds `:53`. `setup.sh` prints the fix: set `DNSStubListener=no`, relink `/etc/resolv.conf`, restart resolved. |
| Containers running as root / wrong file owners | `.env` has the wrong `PUID`/`PGID`, or you edited `UID`/`GID` by hand. Use `PUID`/`PGID` only; re-run `./setup.sh`. |
| Homepage tiles show no live data | Missing API keys in `.env`. See [User guide → Homepage widgets](user-guide.md#homepage-widgets). |
| Homepage can't discover containers | It needs the host docker group. Confirm `DOCKER_GID` in `.env` matches `getent group docker`; re-run `./setup.sh`. |
| Grafana / Prometheus can't write data | Ownership drift. `setup.sh` sets grafana→472, prometheus/data→65534; re-run it. |
| Sonarr/Radarr can't reach Transmission | Use host `transmission` (the container name), **not** `localhost` — they're separate containers on the `matrix` bridge. |
| Reverse-proxy name doesn't resolve | The device isn't using AdGuard for DNS, or the `*.matrix.lan` rewrite is missing. See [User guide → Reverse proxy](user-guide.md#reverse-proxy-setup). |
| Old container lingers after a service was removed | `docker compose up -d --remove-orphans`. |
| `docker compose config` fails on a missing variable | Add it to `.env.example` (this is exactly what the `env-drift` CI guard catches). |

## CI

Every push/PR runs four jobs (`.github/workflows/ci.yml`):

- **shellcheck** — lints `*.sh`.
- **compose-validate** — `docker compose config` against a seeded `.env`.
- **env-drift** — every `${VAR}` in `compose.yml` is documented in `.env.example`.
- **setup-smoke** — runs `setup.sh` twice in a clean `ubuntu:24.04` container
  (proving idempotency) and asserts the generated state.

Keep all four green before merging.
