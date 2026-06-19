# Matrix

Self-hosted home server stack orchestrated with Docker Compose. Bundles the services I run on a single Linux host: a media library (Plex + *arr suite + Transmission + Bazarr + Overseerr), DNS/ad-block (AdGuard Home), reverse proxy (Nginx Proxy Manager), dashboard (Homepage), automatic updates (Watchtower), and an observability stack (cAdvisor + Prometheus + Grafana).

> **📖 Full documentation lives in [`docs/`](docs/README.md).** This README is the
> quick reference. For depth see: [Architecture](docs/architecture.md) ·
> [Deployment](docs/deployment.md) · [User guide (first-run setup)](docs/user-guide.md) ·
> [Operations](docs/operations.md) · [Configuration reference](docs/configuration.md).

## Services

| Service | Image | Host port | Purpose |
| --- | --- | --- | --- |
| Homepage | `ghcr.io/gethomepage/homepage` | `9000` | Service dashboard (auto-discovery via labels) |
| FileBrowser | `filebrowser/filebrowser` | `8090` | Web file manager over the docker tree |
| Nginx Proxy Manager | `jc21/nginx-proxy-manager` | `80`, `81`, `443` | Reverse proxy + Let's Encrypt (single entry point) |
| AdGuard Home | `adguard/adguardhome` | `53`, `8083`, `3000`, `853`, `784` | DNS + ad-block (DoH/DoT/DoQ) |
| Plex | `lscr.io/linuxserver/plex` | host network | Media server |
| Transmission | `lscr.io/linuxserver/transmission` | `9091`, `51413` | Torrent client |
| Sonarr | `lscr.io/linuxserver/sonarr` | `8989` | TV automation |
| Radarr | `lscr.io/linuxserver/radarr` | `7878` | Movie automation |
| Prowlarr | `lscr.io/linuxserver/prowlarr` | `9696` | Indexer manager (syncs to *arr) |
| Bazarr | `lscr.io/linuxserver/bazarr` | `6767` | Subtitle automation |
| Overseerr | `lscr.io/linuxserver/overseerr` | `5055` | Plex content requests |
| Watchtower | `containrrr/watchtower` | — | Image auto-update (opt-in via label) |
| cAdvisor | `gcr.io/cadvisor/cadvisor` | `8082` | Per-container metrics |
| node-exporter | `prom/node-exporter` | — | Host metrics (disk, mem, cpu) |
| Prometheus | `prom/prometheus` | `9090` | Metrics TSDB |
| Grafana | `grafana/grafana` | `3001` | Metrics visualization |

## Requirements

- Linux host (tested on Debian/Ubuntu).
- A non-root user in the `docker` group.
- Roughly the disk you plan to hand to Plex, plus a few GB for service configs and 15 days of Prometheus history.

## Quick start

On a fresh Linux host, clone the repo and run:

```bash
git clone https://github.com/tomibernardin/matrix.git && cd matrix
./setup.sh
```

`setup.sh` is idempotent and auto-elevates with `sudo`. If you must run it directly as root, pass the target user via env — note that sudo's env sanitization means `sudo MATRIX_USER=alice …` won't work; invoke as `MATRIX_USER=alice bash setup.sh` instead. In one pass it:

1. Installs Docker + utilities.
2. Adds your user to the `docker` group.
3. Generates `.env` from the template with auto-detected UID/GID/TZ and random secrets (Transmission password, Grafana admin password) — paths default to `${HOME}/docker`.
4. Creates the directory tree.
5. Seeds Prometheus config and Filebrowser stubs.
6. Applies ownership/permissions (your user, 770; Grafana → UID 472; Prometheus → UID 65534).

Then:

```bash
$EDITOR .env             # optional: add PLEX_CLAIM, override any path/secret
newgrp docker            # pick up the new group, or log out/in
docker compose up -d
```

## `.env`

Never committed. The full list of variables (with comments) lives in [`.env.example`](.env.example). Three categories:

- **Host identity** — `UID`, `GID`, `TZ`.
- **Paths** — `DOCKER_MAIN_ROUTE` and per-service subpaths.
- **Secrets** — `PLEX_CLAIM` (one-shot, get it from <https://www.plex.tv/claim/>), `TRANSMISSION_USER`/`TRANSMISSION_PASS`, `GRAFANA_ADMIN_PASSWORD`. AdGuard's admin password is set during the first-run wizard at `http://host:3000`.

## Day-2 operations

```bash
docker compose ps                    # status (incl. health)
docker compose logs -f <service>     # follow logs
docker compose pull && docker compose up -d   # manual update
docker compose config                # validate compose.yml
```

### Watchtower

Watchtower runs daily at 04:00 local. It is opt-in by label: every `:latest`
service in `compose.yml` already carries

```yaml
labels:
  com.centurylinklabs.watchtower.enable: "true"
```

so they auto-update in place. Plex, AdGuard, Prometheus and Grafana are pinned
to exact tags and deliberately **lack** the label — their upgrades benefit from
a manual review.

### Updating pinned images

The four pinned services don't auto-update. To upgrade one, bump its tag in
`compose.yml` and pull just that service:

```bash
# e.g. Grafana
$EDITOR compose.yml                       # change grafana/grafana:13.0.2 → new tag
docker compose pull grafana && docker compose up -d grafana
```

Resolve the latest tags from each project's releases:
Plex `linuxserver/docker-plex`, AdGuard `AdguardTeam/AdGuardHome`,
Prometheus `prometheus/prometheus`, Grafana `grafana/grafana` (Grafana's Docker
tag has no `v` prefix).

### Homepage

Every service ships with `homepage.*` labels in `compose.yml`, so tiles auto-populate on first `docker compose up -d`. To make the tile links work from devices other than the host, set `HOMEPAGE_HOST` in `.env` to your LAN IP or FQDN.

Live widget data (queue counts, library size, etc.) requires per-service credentials grabbed *after* first launch — paste them into the corresponding variables in `.env` and `docker compose up -d` to apply:

- `SONARR_API_KEY` / `RADARR_API_KEY` / `PROWLARR_API_KEY` / `BAZARR_API_KEY` / `OVERSEERR_API_KEY` — Settings → General → API Key in each web UI.
- `PLEX_TOKEN` — extract from a signed-in browser, see [plexopedia](https://www.plexopedia.com/plex-media-server/general/plex-token/).
- `ADGUARD_USERNAME` / `ADGUARD_PASSWORD` — set during the AdGuard first-run wizard at `http://host:3000`.
- `NPM_USERNAME` / `NPM_PASSWORD` — set on first login to Nginx Proxy Manager at `http://host:81`.

Tiles still render without these; only the widget metrics need them. See <https://gethomepage.dev/> for the full label reference if you want to customize further.

### Observability

Grafana lives at `http://host:3001`, Prometheus at `http://host:9090`, cAdvisor at `http://host:8082`. Prometheus scrapes itself, cAdvisor (per-container metrics) and node-exporter (host disk/mem/cpu).

Everything is provisioned as code, so first launch is just a login:

1. Log in to Grafana (`admin` / `GRAFANA_ADMIN_PASSWORD`). The Prometheus datasource and the "Docker / cAdvisor" dashboard (Grafana ID 14282) are already wired up via `grafana/provisioning/`.
2. Alert rules live in `prometheus/rules.yml` and show up under Prometheus → **Alerts** (`http://host:9090/alerts`): disk <15% free, memory <10% available, container unseen for 5m. There is **no Alertmanager** — no notification channel has been chosen — so alerts are visible but not routed anywhere. Add Alertmanager + a receiver before relying on them for paging.

> All three configs (`prometheus.yml`, `rules.yml`, Grafana provisioning) are repo-owned. `setup.sh` re-copies them into the data tree on every run, so edit them in the repo, `git pull`, re-run `./setup.sh`, and `docker compose up -d`.

### Reverse proxy (recommended setup)

Nginx Proxy Manager owns the host's `:80`/`:443`; AdGuard's admin UI moved to `:8083`. The direct `host:port` mappings are **still open on purpose** (reversible transition) — closing them (binding to `127.0.0.1`) is an optional later step once the proxy is validated. These steps are manual (web UIs):

1. **AdGuard** (`http://host:8083`) → Filters → DNS rewrites → add `*.matrix.lan` → the server's LAN IP. (So `*.matrix.lan` resolves to the box for any device using AdGuard as its DNS.)
2. **NPM** (`http://host:81`) → Proxy Hosts → add one entry per service (scheme `http`, the internal container name + port):

   | Domain | Forward to |
   | --- | --- |
   | `home.matrix.lan` | `homepage:3000` |
   | `files.matrix.lan` | `filebrowser:80` |
   | `adguard.matrix.lan` | `adguardhome:80` |
   | `sonarr.matrix.lan` | `sonarr:8989` |
   | `radarr.matrix.lan` | `radarr:7878` |
   | `bazarr.matrix.lan` | `bazarr:6767` |
   | `requests.matrix.lan` | `overseerr:5055` |
   | `torrent.matrix.lan` | `transmission:9091` |
   | `grafana.matrix.lan` | `grafana:3000` |
   | `prometheus.matrix.lan` | `prometheus:9090` |

NPM reaches every service by container name because they all share the `matrix` bridge network.

## Backup & restore

`setup.sh` installs a root cron job (`/etc/cron.d/matrix-backup`) that runs
[`backup.sh`](backup.sh) nightly at 05:30: it stops the stack (~1 min), tars
`${DOCKER_MAIN_ROUTE}` — excluding Plex media, Transmission downloads and the
Prometheus TSDB, all recoverable — snapshots `.env` alongside, restarts the
stack, and keeps the newest 14 archives in `${BACKUP_DIR}`.

Run one manually any time: `sudo ./backup.sh`

> `${BACKUP_DIR}` should live on a different disk than `${DOCKER_MAIN_ROUTE}`
> if you can. A backup on the same dying disk is not a backup.

### Restore (tested runbook)

On a fresh host (or after wiping a broken tree):

```bash
# 1. Clone and bootstrap (installs Docker, creates the tree, sets permissions).
git clone https://github.com/tomibernardin/matrix.git && cd matrix
./setup.sh

# 2. Stop the (empty) stack if it was started.
docker compose stop

# 3. Restore the .env snapshot — paths and secrets travel with the backup.
install -m 600 /path/to/backups/env-<STAMP> .env

# 4. Unpack the archive over the data tree. DOCKER_MAIN_ROUTE comes from
#    the restored .env; the tar contains the tree's basename (e.g. `docker/`).
source .env
sudo tar -xzf /path/to/backups/matrix-<STAMP>.tar.gz -C "$(dirname "$DOCKER_MAIN_ROUTE")"

# 5. Re-apply ownership/permissions (setup.sh is idempotent and will not
#    touch the restored .env or data, only fix perms and re-seed configs).
./setup.sh

# 6. Bring everything up.
docker compose up -d && docker compose ps
```

Expected result: every service reports healthy and finds its old state —
*arr libraries, NPM proxy hosts and certs, AdGuard config, Grafana dashboards.
Plex media files are NOT in the archive; re-point or re-copy your media into
`${PLEX_MEDIA}` (the library metadata survives in `plex/config`).

## Layout

```
.
├── compose.yml                 # service definitions (source of truth)
├── .env.example                # template for the local .env
├── setup.sh                    # one-shot bootstrap (deps + tree + .env + perms + cron)
├── backup.sh                   # nightly cold backup (cron-installed by setup.sh)
├── prometheus/
│   ├── prometheus.yml          # scrape config (repo-owned, synced into the tree)
│   └── rules.yml               # alert rules (repo-owned)
├── grafana/provisioning/       # datasource + dashboard (repo-owned)
├── scripts/
│   └── check-env-drift.sh      # CI guard: compose vars ⊆ .env.example
├── .github/workflows/
│   └── ci.yml                  # shellcheck, compose-validate, env-drift, setup-smoke
├── docs/                       # full documentation (see docs/README.md)
└── README.md
```
