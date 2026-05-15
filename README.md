# Matrix

Self-hosted home server stack orchestrated with Docker Compose. Bundles the services I run on a single Linux host: a media library (Plex + *arr suite + Transmission), DNS/ad-block (Pi-hole), reverse proxy (Nginx Proxy Manager), and a couple of admin UIs.

## Services

| Service | Image | Host port | Purpose |
| --- | --- | --- | --- |
| Homer | `b4bz/homer` | `9000` | Service dashboard |
| FileBrowser | `filebrowser/filebrowser` | `8090` | Web file manager over the docker tree |
| BudgetZero | `budgetzero/budgetzero` | `8091` | Personal budgeting |
| Nginx Proxy Manager | `jc21/nginx-proxy-manager` | `8000`, `81`, `443` | Reverse proxy + Let's Encrypt |
| Pi-hole | `pihole/pihole` | `53`, `80` | DNS + ad-block |
| Plex | `jaymoulin/plex` | host network | Media server |
| Transmission | `lscr.io/linuxserver/transmission` | `9091`, `51413` | Torrent client |
| Sonarr | `lscr.io/linuxserver/sonarr` | `8989` | TV automation |
| Radarr | `lscr.io/linuxserver/radarr` | `7878` | Movie automation |
| Jackett | `lscr.io/linuxserver/jackett` | `9117` | Indexer aggregator |

## Requirements

- Linux host (tested on Debian/Ubuntu).
- A non-root user in the `docker` group.
- Roughly the disk you plan to hand to Plex, plus a few GB for service configs.

## Quick start

```bash
# 1. Install Docker + utilities (idempotent).
./install.sh

# 2. Create the directory tree under DOCKER_MAIN_ROUTE.
./structure.sh

# 3. Copy the env template and fill it in.
cp .env.example .env
$EDITOR .env   # set UID, GID, TZ, DOCKER_MAIN_ROUTE, PLEX_CLAIM, passwords

# 4. Apply ownership/permissions to the data tree.
./permissions.sh

# 5. Bring the stack up.
docker compose up -d
```

## `.env`

Never committed. The full list of variables (with comments) lives in [`.env.example`](.env.example). Three categories:

- **Host identity** — `UID`, `GID`, `TZ`.
- **Paths** — `DOCKER_MAIN_ROUTE` and per-service subpaths.
- **Secrets** — `PLEX_CLAIM` (one-shot, get it from <https://www.plex.tv/claim/>), `PIHOLE_WEBPASSWORD`, `TRANSMISSION_USER`/`TRANSMISSION_PASS`.

## Day-2 operations

```bash
docker compose ps                    # status
docker compose logs -f <service>     # follow logs
docker compose pull && docker compose up -d   # update images
docker compose config                # validate compose.yml
```

## Backup

The data that matters lives under `${DOCKER_MAIN_ROUTE}`. A minimal backup strategy is to tar that tree (with the stack stopped, to avoid mid-write corruption of SQLite DBs like `filebrowser.db` and Pi-hole's gravity DB):

```bash
docker compose down
sudo tar -C "$(dirname "$DOCKER_MAIN_ROUTE")" -czf matrix-backup-$(date +%F).tar.gz "$(basename "$DOCKER_MAIN_ROUTE")"
docker compose up -d
```

Media (`PLEX_MEDIA`) and torrent downloads are usually excluded — they're recoverable from sources.

## Layout

```
.
├── .env.example      # template for the local .env
├── compose.yml       # service definitions
├── install.sh        # one-shot host bootstrap (docker, utilities)
├── structure.sh      # creates ${DOCKER_MAIN_ROUTE} subdirectories
├── permissions.sh    # chown/chmod the data tree
└── README.md
```
