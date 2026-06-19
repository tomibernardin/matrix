#!/bin/bash
# Matrix one-shot bootstrap.
#
# Run from the project root on a fresh Linux host:
#     ./setup.sh
# (sudo is requested automatically; do NOT run as root directly).
#
# What it does, in order:
#   1. Installs OS utilities + Docker Engine + the docker compose plugin.
#   2. Adds the invoking user to the `docker` group.
#   3. Generates .env from .env.example with auto-detected host values
#      (UID/GID/TZ/$HOME-based data root) and random secrets.
#   4. Creates the directory tree under ${DOCKER_MAIN_ROUTE}.
#   5. Seeds Prometheus config and the Filebrowser db/settings stubs.
#   6. Applies ownership (your user) and permissions (770) across the tree,
#      plus the special UIDs for Grafana (472) and Prometheus (65534).
#
# Re-running is safe: every step is idempotent.

set -euo pipefail

# ----------------------------------------------------------------------------
# 0. Re-exec with sudo, preserving the invoking user.
# ----------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    echo ">>> Elevating with sudo..."
    exec sudo --preserve-env=MATRIX_USER bash "$0" "$@"
fi

# Resolve the *real* user — the one who invoked sudo, not root.
REAL_USER="${MATRIX_USER:-${SUDO_USER:-}}"
if [[ -z "${REAL_USER}" || "${REAL_USER}" == "root" ]]; then
    cat >&2 <<'ERR'
ERROR: cannot determine a non-root user.

Run this script via sudo from a regular user:
    ./setup.sh

Or, if you really must run it as root, set MATRIX_USER to the target
account (it must already exist):
    MATRIX_USER=alice bash setup.sh
ERR
    exit 1
fi

if ! id "${REAL_USER}" >/dev/null 2>&1; then
    echo "ERROR: user '${REAL_USER}' does not exist on this host." >&2
    exit 1
fi

REAL_UID="$(id -u "${REAL_USER}")"
REAL_GID="$(id -g "${REAL_USER}")"
REAL_HOME="$(getent passwd "${REAL_USER}" | cut -d: -f6)"
TZ_DETECTED="$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================================"
echo " Matrix bootstrap"
echo "  User:      ${REAL_USER}  (UID=${REAL_UID}, GID=${REAL_GID})"
echo "  Home:      ${REAL_HOME}"
echo "  Timezone:  ${TZ_DETECTED}"
echo "  Repo:      ${SCRIPT_DIR}"
echo "================================================================"

# Warn early about the classic AdGuard-vs-systemd-resolved port 53 clash.
# We don't disable it automatically — that's a host-wide DNS change that
# the operator should make consciously. Skip silently if `ss` isn't
# available yet (rare on real distros, but possible in minimal containers).
if command -v ss >/dev/null \
   && ss -tulpn 2>/dev/null | grep -qE ':53\b.*systemd-resolve'; then
    cat >&2 <<'WARN'
WARNING: systemd-resolved is listening on port 53.
AdGuard Home will fail to bind :53 until you free it. Typical fix:

    sudo sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
    sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    sudo systemctl restart systemd-resolved

WARN
fi

# ----------------------------------------------------------------------------
# 1. Host packages and Docker.
# ----------------------------------------------------------------------------
echo
echo ">>> [1/6] Installing host packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    nano tree htop net-tools unzip \
    ca-certificates curl openssl

if ! command -v docker >/dev/null; then
    echo ">>> Installing Docker Engine..."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
else
    echo ">>> Docker already installed ($(docker --version))."
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: 'docker compose' plugin missing — get.docker.com should have installed it." >&2
    exit 1
fi

usermod -aG docker "${REAL_USER}"

# Resolve the host docker group GID — required for non-root services
# that need to read /var/run/docker.sock (e.g. Homepage discovery).
DOCKER_GID="$(getent group docker | cut -d: -f3)"
if [[ -z "${DOCKER_GID}" ]]; then
    echo "ERROR: failed to resolve the 'docker' group GID." >&2
    exit 1
fi

# ----------------------------------------------------------------------------
# 2. Seed .env from .env.example.
# ----------------------------------------------------------------------------
echo
echo ">>> [2/6] Generating .env (if absent)..."
ENV_FILE="${SCRIPT_DIR}/.env"
DOCKER_MAIN_ROUTE_DEFAULT="${REAL_HOME}/docker"

if [[ -f "${ENV_FILE}" ]]; then
    echo ">>> .env already exists, leaving it untouched."
else
    cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"

    # Substitute detected values.
    sed -i \
        -e "s|^PUID=.*|PUID=${REAL_UID}|" \
        -e "s|^PGID=.*|PGID=${REAL_GID}|" \
        -e "s|^DOCKER_GID=.*|DOCKER_GID=${DOCKER_GID}|" \
        -e "s|^TZ=.*|TZ=${TZ_DETECTED}|" \
        -e "s|^DOCKER_MAIN_ROUTE=.*|DOCKER_MAIN_ROUTE=${DOCKER_MAIN_ROUTE_DEFAULT}|" \
        -e "s|^BACKUP_DIR=.*|BACKUP_DIR=${REAL_HOME}/matrix-backups|" \
        "${ENV_FILE}"

    # Generate random secrets (URL/shell-safe).
    rand_secret() { openssl rand -base64 24 | tr -d '/=+' | cut -c1-24; }
    TRANS_PASS="$(rand_secret)"
    GRAFANA_PASS="$(rand_secret)"
    sed -i \
        -e "s|^TRANSMISSION_USER=.*|TRANSMISSION_USER=admin|" \
        -e "s|^TRANSMISSION_PASS=.*|TRANSMISSION_PASS=${TRANS_PASS}|" \
        -e "s|^GRAFANA_ADMIN_PASSWORD=.*|GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASS}|" \
        "${ENV_FILE}"

    chown "${REAL_UID}:${REAL_GID}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    echo ">>> .env generated with random secrets at ${ENV_FILE} (mode 600)."
fi

# Load .env so DOCKER_MAIN_ROUTE / paths are usable below.
set -a
# shellcheck source=.env.example
source "${ENV_FILE}"
set +a

: "${DOCKER_MAIN_ROUTE:?DOCKER_MAIN_ROUTE missing from .env}"

# ----------------------------------------------------------------------------
# 3. Directory structure.
# ----------------------------------------------------------------------------
echo
echo ">>> [3/6] Creating directory tree under ${DOCKER_MAIN_ROUTE}..."
mkdir -p "${DOCKER_MAIN_ROUTE}"/{homepage/config,filebrowser/{config,database},nginxpm/{config,etc},adguardhome/{work,conf},plex/{config,temp,media/{anime,movies,series,homevideos}},transmission/{config,watch,downloads/{complete,incomplete}},sonarr/config,radarr/config,prowlarr/config,bazarr/config,overseerr/config,prometheus/{config,data},grafana/{data,provisioning}}

# ----------------------------------------------------------------------------
# 4. Seed config files that bind-mount targets expect as actual files.
# ----------------------------------------------------------------------------
echo
echo ">>> [4/6] Seeding initial config files..."

# Prometheus + Grafana configs are repo-owned: re-copied on every run so the
# repo stays the source of truth. Data dirs are never touched.
cp -f "${SCRIPT_DIR}/prometheus/prometheus.yml" "${DOCKER_MAIN_ROUTE}/prometheus/config/prometheus.yml"
cp -f "${SCRIPT_DIR}/prometheus/rules.yml"      "${DOCKER_MAIN_ROUTE}/prometheus/config/rules.yml"
cp -rf "${SCRIPT_DIR}/grafana/provisioning/."   "${DOCKER_MAIN_ROUTE}/grafana/provisioning/"
echo ">>> Synced Prometheus + Grafana configs from repo."

# Filebrowser bind-mounts its db and settings.json as files. If the host
# paths don't exist yet, Docker would create them as directories and
# Filebrowser would fail to load.
FB_DB="${FILEBROWSER_DATABASE}"
FB_CFG="${FILEBROWSER_CONFIG}"
[[ -f "${FB_DB}"  ]] || : > "${FB_DB}"
[[ -f "${FB_CFG}" ]] || echo '{}' > "${FB_CFG}"

# ----------------------------------------------------------------------------
# 5. Ownership and permissions.
# ----------------------------------------------------------------------------
echo
echo ">>> [5/6] Applying ownership and permissions..."

# Default: everything owned by the invoking user, group-writable, world none.
chown -R "${REAL_UID}:${REAL_GID}" "${DOCKER_MAIN_ROUTE}"
chmod -R u=rwX,g=rwX,o= "${DOCKER_MAIN_ROUTE}"

# Grafana's container runs as UID 472 (see USER grafana in grafana/grafana
# Dockerfile). Pin the whole grafana tree (data + provisioning) so it can
# read its provisioned datasource/dashboards and write grafana.db.
chown -R 472:472 "${DOCKER_MAIN_ROUTE}/grafana"

# Prometheus runs as UID 65534 (nobody) per prom/prometheus Dockerfile.
chown -R 65534:65534 "${DOCKER_MAIN_ROUTE}/prometheus/data"
# Keep its configs readable by the container.
chown 65534:65534 "${DOCKER_MAIN_ROUTE}/prometheus/config/prometheus.yml"
chown 65534:65534 "${DOCKER_MAIN_ROUTE}/prometheus/config/rules.yml"

# ----------------------------------------------------------------------------
# 6. Nightly backup cron job.
# ----------------------------------------------------------------------------
echo
echo ">>> [6/6] Installing nightly backup cron job..."
cat > /etc/cron.d/matrix-backup <<CRON
# Nightly Matrix backup — 05:30, after Watchtower's 04:00 window.
# Installed by setup.sh; edit/remove freely.
30 5 * * * root ${SCRIPT_DIR}/backup.sh >> /var/log/matrix-backup.log 2>&1
CRON
chmod 644 /etc/cron.d/matrix-backup

# ----------------------------------------------------------------------------
# Done.
# ----------------------------------------------------------------------------
cat <<MSG

================================================================
 Matrix bootstrap complete.
================================================================
  Data root:       ${DOCKER_MAIN_ROUTE}
  .env file:       ${ENV_FILE}   (mode 600, owned by ${REAL_USER})

  Generated secrets (already written to .env):
    - TRANSMISSION_USER / TRANSMISSION_PASS
    - GRAFANA_ADMIN_PASSWORD

  Inspect with:
    sudo -u ${REAL_USER} grep -E '_PASS|_PASSWORD|_USER' ${ENV_FILE}

  Next steps:
    1. (Optional) Get a Plex claim token (valid 4 min) and put it in .env:
         https://www.plex.tv/claim/

    2. Pick up the new docker group membership for ${REAL_USER}:
         log out and back in, OR run interactively:  newgrp docker

    3. Start the stack:
         cd ${SCRIPT_DIR}
         docker compose up -d

    4. First-time per-service setup:
         - AdGuard wizard:  http://<host>:3000
         - Grafana login:   http://<host>:3001  (admin / GRAFANA_ADMIN_PASSWORD)

  A nightly backup runs at 05:30 (/etc/cron.d/matrix-backup → ${BACKUP_DIR}).
  Run one now with: sudo ${SCRIPT_DIR}/backup.sh
================================================================
MSG
