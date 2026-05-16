# Matrix

Self-hosted home server stack orchestrated with Docker Compose. Bundles the services I run on a single Linux host: a media library (Plex + *arr suite + Transmission + Bazarr + Overseerr), DNS/ad-block (AdGuard Home), reverse proxy (Nginx Proxy Manager), dashboard (Homepage), automatic updates (Watchtower), and an observability stack (cAdvisor + Prometheus + Grafana).

## Services

| Service | Image | Host port | Purpose |
| --- | --- | --- | --- |
| Homepage | `ghcr.io/gethomepage/homepage` | `9000` | Service dashboard (auto-discovery via labels) |
| FileBrowser | `filebrowser/filebrowser` | `8090` | Web file manager over the docker tree |
| BudgetZero | `budgetzero/budgetzero` | `8091` | Personal budgeting |
| Nginx Proxy Manager | `jc21/nginx-proxy-manager` | `8000`, `81`, `443` | Reverse proxy + Let's Encrypt |
| AdGuard Home | `adguard/adguardhome` | `53`, `80`, `3000`, `853`, `784` | DNS + ad-block (DoH/DoT/DoQ) |
| Plex | `lscr.io/linuxserver/plex` | host network | Media server |
| Transmission | `lscr.io/linuxserver/transmission` | `9091`, `51413` | Torrent client |
| Sonarr | `lscr.io/linuxserver/sonarr` | `8989` | TV automation |
| Radarr | `lscr.io/linuxserver/radarr` | `7878` | Movie automation |
| Jackett | `lscr.io/linuxserver/jackett` | `9117` | Indexer aggregator |
| Bazarr | `lscr.io/linuxserver/bazarr` | `6767` | Subtitle automation |
| Overseerr | `lscr.io/linuxserver/overseerr` | `5055` | Plex content requests |
| Watchtower | `containrrr/watchtower` | — | Image auto-update (opt-in via label) |
| cAdvisor | `gcr.io/cadvisor/cadvisor` | `8082` | Per-container metrics |
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

Watchtower runs daily at 04:00 local. It is opt-in by label — add this to any service you want auto-updated:

```yaml
labels:
  com.centurylinklabs.watchtower.enable: "true"
```

Plex, AdGuard, Prometheus and Grafana are left out of rotation by default because their upgrades benefit from a manual review.

### Homepage

Every service ships with `homepage.*` labels in `compose.yml`, so tiles auto-populate on first `docker compose up -d`. To make the tile links work from devices other than the host, set `HOMEPAGE_HOST` in `.env` to your LAN IP or FQDN.

Live widget data (queue counts, library size, etc.) requires per-service credentials grabbed *after* first launch — paste them into the corresponding variables in `.env` and `docker compose up -d` to apply:

- `SONARR_API_KEY` / `RADARR_API_KEY` / `JACKETT_API_KEY` / `BAZARR_API_KEY` / `OVERSEERR_API_KEY` — Settings → General → API Key in each web UI.
- `PLEX_TOKEN` — extract from a signed-in browser, see [plexopedia](https://www.plexopedia.com/plex-media-server/general/plex-token/).
- `ADGUARD_USERNAME` / `ADGUARD_PASSWORD` — set during the AdGuard first-run wizard at `http://host:3000`.
- `NPM_USERNAME` / `NPM_PASSWORD` — set on first login to Nginx Proxy Manager at `http://host:81`.

Tiles still render without these; only the widget metrics need them. See <https://gethomepage.dev/> for the full label reference if you want to customize further.

### Observability

Grafana lives at `http://host:3001`, Prometheus at `http://host:9090`, cAdvisor at `http://host:8082`. On first launch:

1. Log in to Grafana (`admin` / `GRAFANA_ADMIN_PASSWORD`).
2. Add Prometheus as a data source (`http://prometheus:9090`).
3. Import dashboard ID **14282** (Docker / cAdvisor) for a per-container overview.

## Backup

The data that matters lives under `${DOCKER_MAIN_ROUTE}`. Stop the stack first to avoid mid-write corruption of SQLite/TSDB files (`filebrowser.db`, AdGuard's DB, Prometheus TSDB):

```bash
docker compose down
sudo tar -C "$(dirname "$DOCKER_MAIN_ROUTE")" -czf matrix-backup-$(date +%F).tar.gz "$(basename "$DOCKER_MAIN_ROUTE")"
docker compose up -d
```

Media (`PLEX_MEDIA`) and torrent downloads are usually excluded — they're recoverable from sources.

## Layout

```
.
├── .env.example          # template for the local .env
├── compose.yml           # service definitions
├── setup.sh              # one-shot bootstrap (deps + tree + .env + permissions)
├── prometheus/
│   └── prometheus.yml    # seed config copied into the volume on first run
├── .github/workflows/
│   └── ci.yml            # shellcheck + docker compose config
└── README.md
```
