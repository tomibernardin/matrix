#!/bin/bash
# Run a local SonarQube analysis of this repo, with shellcheck findings
# imported as external issues.
#
# SonarQube has no Bash analyzer and docker-compose isn't one of its supported
# IaC formats, so without the shellcheck import it indexes zero files and its
# quality gate is meaningless here. The import creates the file components and
# attaches the findings, which is what makes the dashboard say anything real.
#
# Usage:
#   SONAR_TOKEN=<token> ./scripts/sonar-scan.sh
#
# The token is read from the environment and is never written to the repo —
# no sonar-project.properties, no committed report. Generate one under
# My Account -> Security in the SonarQube UI.
#
# Requires: Docker (shellcheck + scanner run as containers) and python3.
set -euo pipefail

: "${SONAR_TOKEN:?SONAR_TOKEN must be set in the environment}"
SONAR_HOST_URL="${SONAR_HOST_URL:-http://host.docker.internal:9000}"
PROJECT_KEY="${SONAR_PROJECT_KEY:-matrix}"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_DIR}"

# Reports are build artifacts: kept out of git via .gitignore.
OUT_DIR=".sonar"
mkdir -p "${OUT_DIR}"

PY=python3
command -v "${PY}" >/dev/null 2>&1 || PY=python

# Docker needs a native path for -v on Windows; MSYS must not rewrite it.
HOST_PATH="${REPO_DIR}"
if command -v cygpath >/dev/null 2>&1; then
    HOST_PATH="$(cygpath -w "${REPO_DIR}")"
fi
export MSYS_NO_PATHCONV=1

mapfile -t SCRIPTS < <(git ls-files '*.sh')
echo ">>> [1/3] shellcheck over ${#SCRIPTS[@]} script(s)..."
# Note: a non-zero exit just means findings exist; that's data, not failure.
docker run --rm -v "${HOST_PATH}:/mnt" -w /mnt koalaman/shellcheck:stable \
    -f json1 -S style "${SCRIPTS[@]}" > "${OUT_DIR}/shellcheck.json" || true

echo ">>> [2/3] converting to SonarQube generic issue format..."
"${PY}" scripts/shellcheck-to-sonar.py \
    "${OUT_DIR}/shellcheck.json" "${OUT_DIR}/shellcheck-sonar.json"

echo ">>> [3/3] running the scanner..."
# git safe.directory: the mount is owned by another UID inside the container,
# and without it git refuses to run, which silently disables sonar.text.inclusions.
docker run --rm \
    -v "${HOST_PATH}:/usr/src" \
    -e SONAR_HOST_URL="${SONAR_HOST_URL}" \
    -e SONAR_TOKEN="${SONAR_TOKEN}" \
    -e GIT_CONFIG_COUNT=1 \
    -e GIT_CONFIG_KEY_0=safe.directory \
    -e GIT_CONFIG_VALUE_0=/usr/src \
    sonarsource/sonar-scanner-cli \
    -Dsonar.projectKey="${PROJECT_KEY}" \
    -Dsonar.sources=. \
    -Dsonar.exclusions="**/.git/**,${OUT_DIR}/**" \
    -Dsonar.text.inclusions='**/*' \
    -Dsonar.externalIssuesReportPaths="${OUT_DIR}/shellcheck-sonar.json" \
    -Dsonar.working.directory=/tmp/scannerwork

echo
echo ">>> Done: ${SONAR_HOST_URL%/}/dashboard?id=${PROJECT_KEY}"
