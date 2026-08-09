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

## Local SonarQube analysis

Run after finishing a task:

```bash
SONAR_TOKEN=<your-token> ./scripts/sonar-scan.sh
```

The token comes from the environment and is **never** committed — no
`sonar-project.properties` carrying a secret. Generate one under
My Account → Security in the SonarQube UI. Override the server with
`SONAR_HOST_URL` (default `http://host.docker.internal:9000`, i.e. the host's
SonarQube as seen from the scanner container).

[`scripts/sonar-scan.sh`](../scripts/sonar-scan.sh) does three things:

1. Runs **shellcheck** (container) over every `*.sh` tracked by git → `json1`.
2. Converts those findings to SonarQube's generic issue format via
   [`scripts/shellcheck-to-sonar.py`](../scripts/shellcheck-to-sonar.py).
3. Runs the scanner (container), importing them with
   `sonar.externalIssuesReportPaths`.

Reports land in `.sonar/` (gitignored). No local install of `sonar-scanner` or
`shellcheck` is needed — both run as containers; `docker` and `python3` are the
only prerequisites.

### Why the shellcheck import exists

SonarQube has no Bash analyzer, and `compose.yml` isn't one of its supported IaC
formats (Dockerfile, Kubernetes, Terraform and CloudFormation are). Without the
import it indexes **zero** files and its quality gate is vacuous. Importing
shellcheck findings creates the file components and attaches the issues, so the
dashboard finally reflects the part of this repo that is actual code.

Two implementation details worth keeping:

- **`git safe.directory`** is passed into the scanner container. The mount is
  owned by another UID inside the container; without it git refuses to run,
  which silently disables `sonar.text.inclusions`.
- **Issues are reported at line granularity.** Sonar validates text ranges
  against indexed content, and these files have no language, so column-level
  ranges risk rejection.

### Known state of the quality gate

The gate currently reports **ERROR** on `new_coverage` (0% < 80%): the only
natively-analysed code is the Python helper, and it has no tests. That
condition is the default "Sonar way" policy for application code and is a poor
fit for an infrastructure repo. Resolve it deliberately — either add tests for
the helper and import coverage via `sonar.python.coverage.reportPaths`, or scope
coverage out with `sonar.coverage.exclusions=scripts/**` — rather than reading
the red gate as a defect in the stack itself. The shell findings are reported
separately and are all `MINOR` today.

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
