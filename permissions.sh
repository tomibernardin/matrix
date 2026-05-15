#!/bin/bash
# Set ownership and conservative permissions on the docker data tree.
# Container UID/GID come from .env (PUID/PGID match these); root keeps
# write through the docker group, the rest of the world stays out.
set -euo pipefail

# Load .env so DOCKER_MAIN_ROUTE / UID / GID are available.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/.env"

: "${DOCKER_MAIN_ROUTE:?DOCKER_MAIN_ROUTE must be set in .env}"
: "${UID:?UID must be set in .env}"
: "${GID:?GID must be set in .env}"

sudo chown -R "${UID}:${GID}" "${DOCKER_MAIN_ROUTE}"
# 770 = owner + group rwx, world nothing. Sensitive configs (NPM letsencrypt,
# filebrowser.db, Pi-hole DNS) must not be world-readable.
sudo chmod -R u=rwX,g=rwX,o= "${DOCKER_MAIN_ROUTE}"

echo "Permisos actualizados en ${DOCKER_MAIN_ROUTE}"
