# Matrix documentation

Full documentation for the Matrix self-hosted stack. The top-level
[`README.md`](../README.md) is the quick reference; these documents go deeper.

## Start here

| If you want to… | Read |
| --- | --- |
| Understand how the stack is built and why | [Architecture](architecture.md) |
| Install Matrix on a fresh server | [Deployment guide](deployment.md) |
| Finish first-run setup of each service (the manual steps) | [User guide](user-guide.md) |
| Run, update, back up, restore, or troubleshoot it | [Operations](operations.md) |
| Look up what every `.env` variable does | [Configuration reference](configuration.md) |
| Change the stack (add a service, the PR/CI workflow) | [Contributing & maintaining](contributing.md) |

## The 10-minute path

1. [Deploy](deployment.md) → `git clone … && ./setup.sh`.
2. Put a `PLEX_CLAIM` in `.env`, then `docker compose up -d`.
3. Walk the [User guide](user-guide.md) once, top to bottom — it covers every
   click you have to do by hand (Plex claim, AdGuard wizard, NPM proxy hosts,
   Prowlarr indexers, Homepage widget keys).
4. Skim [Operations](operations.md) so you know where backups land and how
   updates happen.

## Audience

This is a single-operator homelab on one Linux host. The docs assume you have
shell access to that host and are comfortable editing a `.env` file and running
`docker compose`. No Kubernetes, no multi-tenant concerns.

## Keeping docs honest

Service names, ports and `.env` variables in these files mirror
[`compose.yml`](../compose.yml) and [`.env.example`](../.env.example). CI
(`env-drift`) fails if compose references a variable the template doesn't
document, so the configuration reference can't silently drift. If you change a
port or add a service, update the affected doc in the same PR.
