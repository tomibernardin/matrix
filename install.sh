#!/bin/bash
# Bootstrap a host for the Matrix stack: install utilities, install Docker
# (CE + compose plugin), and add the invoking user to the `docker` group.
set -euo pipefail

if ! command -v sudo >/dev/null; then
    echo "sudo is required" >&2
    exit 1
fi

# Utilities used by day-2 ops and the other scripts.
sudo apt-get update
sudo apt-get install -y nano tree htop net-tools unzip ca-certificates curl

# Install Docker Engine + the `docker compose` plugin.
if ! command -v docker >/dev/null; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
fi

# `docker compose` (plugin) ships with the Docker convenience script above.
# The old `docker-compose` v1 (Python) is deprecated — we intentionally do
# not install it.

sudo usermod -aG docker "${USER}"

cat <<'MSG'

Docker is installed. The current shell still belongs to your old group set;
log out and back in (or run `newgrp docker` interactively) so that
`docker compose ...` works without sudo. Then continue with:

    ./structure.sh
    cp .env.example .env && $EDITOR .env
    ./permissions.sh
    docker compose up -d

MSG
