# Contributing & maintaining

How to make changes to Matrix safely. This is the maintainer's companion to the
[Architecture](architecture.md) doc — it documents the workflow and conventions
the repo already follows so future changes stay consistent.

## Development workflow

`main` is always deployable. Every change goes through a PR with green CI.

```bash
git checkout main && git pull
git checkout -b short-descriptive-branch

# ...make changes, validate locally (see below)...

git add -A && git commit -m "type(scope): summary"
git push -u origin short-descriptive-branch
gh pr create --base main --fill            # then wait for CI
gh pr merge <N> --squash --delete-branch   # once the 4 jobs are green

git checkout main && git pull
git branch -D short-descriptive-branch && git remote prune origin
```

PRs are **squash-merged**, so the branch's commits collapse into one — keep the
PR focused on a single change.

## Local validation before pushing

Run what CI runs; catch failures before the round-trip:

```bash
# compose parses and interpolates (needs a .env; .env.example works)
cp .env.example .env && docker compose config --quiet; echo $?; rm -f .env

# every ${VAR} in compose.yml is documented in .env.example
bash scripts/check-env-drift.sh

# shell scripts are syntactically sound (CI also runs shellcheck)
bash -n setup.sh && bash -n backup.sh
```

## CI gates (`.github/workflows/ci.yml`)

Four jobs must pass to merge:

| Job | Checks |
| --- | --- |
| `shellcheck` | Lints every `*.sh` (severity: warning). |
| `compose-validate` | `docker compose config` against a seeded `.env`. |
| `env-drift` | Every `${VAR}` in `compose.yml` is documented in `.env.example`. |
| `setup-smoke` | Runs `setup.sh` twice in a clean `ubuntu:24.04` container (idempotency) and asserts the generated state. |

If `setup-smoke` fails, read it with `gh run view <id> --log-failed`. Common
gotcha: container `run` steps default to `sh`; use `set -o pipefail` only under
`bash` (the job pins `defaults.run.shell: bash`).

## Adding a service

The repeatable pattern — touch these in one PR:

1. **`compose.yml`** — add the service block. Reuse the anchors and conventions:
   - `networks: [matrix]`; for LinuxServer images `environment: {<<: *lsio}`.
   - `healthcheck: {<<: *hc, test: [...]}` (the `x-healthcheck` anchor supplies
     interval/timeout/retries).
   - `homepage.*` labels so it appears on the dashboard (group, name, icon,
     href using `${HOMEPAGE_HOST:-localhost}:<port>`, and a widget if supported).
   - **Update policy** (see below): either pin the tag *or* add
     `com.centurylinklabs.watchtower.enable: "true"`.
2. **`.env.example`** — add any `${VAR}` the service references (path under
   `${DOCKER_MAIN_ROUTE}`, plus a widget API-key line if applicable). Skipping
   this fails the `env-drift` gate.
3. **`setup.sh`** — add the service's directory to the `mkdir -p` brace list. If
   the image runs as a fixed non-root UID (like Grafana 472 / Prometheus 65534),
   add a matching `chown` in the permissions phase.
4. **Docs** — add a row to the service table in [`README.md`](../README.md) and
   the [architecture](architecture.md) "Services by role" list; if it needs
   first-run setup, add a section to the [User guide](user-guide.md).
5. **Validate** locally (above), push, PR.

Removing a service is the reverse; remember operators need
`docker compose up -d --remove-orphans` to retire the old container, and the
data dir is left on disk on purpose.

## Update policy: pin vs `:latest`

- **Pin to an exact tag** if a bad upgrade is disruptive and benefits from a
  human look (Plex, AdGuard, Prometheus, Grafana). Pinned services carry **no**
  Watchtower label. Document the bump procedure expectation in
  [Operations → Updating](operations.md#updating-images).
- **Otherwise `:latest` + the Watchtower label** so it auto-updates daily.

## Editing repo-owned configs

`prometheus/prometheus.yml`, `prometheus/rules.yml` and
`grafana/provisioning/**` are copied into the data tree by `setup.sh` on every
run. Edit them **in the repo**, not in `${DOCKER_MAIN_ROUTE}` (those copies get
overwritten). See [Operations](operations.md#editing-repo-owned-configs).

## Conventions

- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `chore:`, `ci:`, `docs:`), with a body explaining *why*.
  Use `feat(scope)!:` for breaking changes (e.g. removing a service).
- **`.env` is never committed.** Only `.env.example` (no real secrets) is.
- **Identity:** use `PUID`/`PGID`, never `UID`/`GID` (bash readonly built-ins;
  resolve to 0 under `sudo`).
- **Line endings:** `.gitattributes` forces LF on `*.sh`/`*.yml`/`*.yaml`/
  `*.json`. Executable bit on scripts doesn't survive a Windows checkout — after
  `git add`, run `git update-index --chmod=+x <script>` and confirm `100755`
  with `git ls-files --stage`.
- **Docs stay current:** change a port/service/variable → update the affected doc
  in the same PR.
