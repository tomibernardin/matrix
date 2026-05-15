#!/bin/bash
# Create the directory tree expected by compose.yml under DOCKER_MAIN_ROUTE.
# Idempotent — safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/.env"

: "${DOCKER_MAIN_ROUTE:?DOCKER_MAIN_ROUTE must be set in .env}"

mkdir -p "${DOCKER_MAIN_ROUTE}"/{homer/config,filebrowser/{config,database},nginxpm/{config,etc},pihole/{config,dnsmasq},plex/{config,temp,media/{anime,movies,series,homevideos}},transmission/{config,watch,downloads/{complete,incomplete}},sonarr/config,radarr/config,jackett/config}

echo "Directorios creados/verificados en ${DOCKER_MAIN_ROUTE}"
