#!/bin/bash
# CI guard: every ${VAR} referenced in compose.yml must be documented in
# .env.example. Catches the class of bug where a new compose variable is
# added but the template (and thus setup.sh's generated .env) lags behind.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

mapfile -t refs < <(
    grep -oE '\$\{[A-Z_][A-Z0-9_]*(:-[^}]*)?\}' compose.yml \
    | sed -E 's/^\$\{([A-Z_][A-Z0-9_]*).*/\1/' \
    | sort -u
)

missing=0
for var in "${refs[@]}"; do
    if ! grep -qE "^${var}=" .env.example; then
        echo "MISSING in .env.example: ${var}" >&2
        missing=1
    fi
done

if [[ "${missing}" -eq 0 ]]; then
    echo "OK: all ${#refs[@]} compose variables are documented in .env.example"
fi
exit "${missing}"
