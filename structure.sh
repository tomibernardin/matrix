#!/bin/bash
# Create the directory tree expected by compose.yml under DOCKER_MAIN_ROUTE.
# Idempotent — safe to re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/.env"

: "${DOCKER_MAIN_ROUTE:?DOCKER_MAIN_ROUTE must be set in .env}"

mkdir -p "${DOCKER_MAIN_ROUTE}"/{homepage/config,filebrowser/{config,database},nginxpm/{config,etc},adguardhome/{work,conf},plex/{config,temp,media/{anime,movies,series,homevideos}},transmission/{config,watch,downloads/{complete,incomplete}},sonarr/config,radarr/config,jackett/config,bazarr/config,overseerr/config,prometheus/{config,data},grafana/data}

# Seed Prometheus config from the repo if not present.
if [[ ! -f "${DOCKER_MAIN_ROUTE}/prometheus/config/prometheus.yml" ]]; then
    cp "${SCRIPT_DIR}/prometheus/prometheus.yml" \
       "${DOCKER_MAIN_ROUTE}/prometheus/config/prometheus.yml"
    echo "Sembrado prometheus.yml por defecto"
fi

echo "Directorios creados/verificados en ${DOCKER_MAIN_ROUTE}"
