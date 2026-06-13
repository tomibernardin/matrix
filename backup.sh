#!/bin/bash
# Nightly cold backup of the Matrix data tree.
#
# Stops the stack (≈1 min downtime), tars ${DOCKER_MAIN_ROUTE} minus
# recoverable bulk (media, downloads, prometheus TSDB), snapshots the repo's
# .env next to it, restarts the stack, and keeps the newest 14 archives.
#
# Installed as a root cron job by setup.sh (05:30, after Watchtower's 04:00
# update window). Can also be run manually: sudo ./backup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set -a
# shellcheck source=.env.example
source "${SCRIPT_DIR}/.env"
set +a

: "${DOCKER_MAIN_ROUTE:?DOCKER_MAIN_ROUTE missing from .env}"
: "${BACKUP_DIR:?BACKUP_DIR missing from .env}"

KEEP=14
STAMP="$(date +%F_%H%M)"
PARENT="$(dirname "${DOCKER_MAIN_ROUTE}")"
BASE="$(basename "${DOCKER_MAIN_ROUTE}")"

mkdir -p "${BACKUP_DIR}"

cd "${SCRIPT_DIR}"
echo ">>> ${STAMP}: stopping stack..."
docker compose stop

echo ">>> Archiving ${DOCKER_MAIN_ROUTE}..."
tar -czf "${BACKUP_DIR}/matrix-${STAMP}.tar.gz" \
    --exclude="${BASE}/plex/media" \
    --exclude="${BASE}/plex/temp" \
    --exclude="${BASE}/transmission/downloads" \
    --exclude="${BASE}/prometheus/data" \
    -C "${PARENT}" "${BASE}"

# .env holds the secrets that make the archive restorable — keep it next to it.
install -m 600 "${SCRIPT_DIR}/.env" "${BACKUP_DIR}/env-${STAMP}"

echo ">>> Restarting stack..."
docker compose up -d

echo ">>> Pruning to the newest ${KEEP} archives..."
ls -1t "${BACKUP_DIR}"/matrix-*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" | xargs -r rm -f
ls -1t "${BACKUP_DIR}"/env-* 2>/dev/null | tail -n "+$((KEEP + 1))" | xargs -r rm -f

echo ">>> Backup complete: ${BACKUP_DIR}/matrix-${STAMP}.tar.gz"
