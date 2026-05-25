# AGENTS.md

## Project

Docker image that backs up Actual Budget data to rclone remotes. Runs on Alpine (base: `rclone/rclone`), scheduled via `supercronic`.

## Architecture

```
scripts/entrypoint.sh   → ENTRYPOINT: loads env, checks rclone, starts cron or one-shot backup
scripts/includes.sh     → Shared functions: env loading, rclone checks, notifications
scripts/backup.sh       → Orchestrates: download → zip → upload → cleanup → notify
scripts/download-actual-budget.js → Uses @actual-app/api to download budgets (CommonJS, minimist)
```

No monorepo. No repo-level package.json or lockfile. `npm install` happens inside the container at runtime (`/app/node_modules`).

## Languages and Style

- **Bash** (primary): 4-space indentation, ShellCheck annotations (`# shellcheck source=`, `# shellcheck disable=`)
- **JavaScript**: CommonJS (`require`), 2-space indentation
- **EditorConfig** enforced: UTF-8, LF line endings, trailing whitespace trimmed (except `.md`)

## Build and Test

Automated tests are driven through `Makefile`.

```sh
# Lint, ShellCheck, and JS syntax checks
make lint

# Node unit tests for scripts/download-actual-budget.js
make test-node

# Build the production image and test image
make test-image

# Run Docker-based shell orchestration tests
make test-container

# Full local test flow
make test
```

Docker-based tests require a running Docker daemon. On macOS, either Docker Desktop or Colima is acceptable. If using Colima:

```sh
brew install docker colima
colima start
make test
```

Manual verification examples:

```sh
# Build the Docker image
docker build -t actualbudget-backup .

# Run a one-shot backup (requires rclone config and env vars)
docker run --rm -v /path/to/rclone.conf:/config/rclone/rclone.conf --env-file .env actualbudget-backup backup
```

## Key Patterns

- **Environment variable loading**: `get_env` in `includes.sh` resolves values from: env var → `*_FILE` secret path → `.env` file (DOTENV_ prefix). All env vars support the `_FILE` suffix for Docker secrets.
- **Numbered list vars**: Multiple sync IDs (`ACTUAL_BUDGET_SYNC_ID_0`, `_1`, `_2`...) and rclone remotes (`RCLONE_REMOTE_NAME_0`, `RCLONE_REMOTE_DIR_0`...) are parsed in order; parsing stops at the first gap.
- **Container runtime deps**: `bash`, `supercronic`, `curl`, `jq`, `zip`, `nodejs`, `npm`, `wget`, `tar`, `xz`, `grep`, `file`, `rclone`

## Gotchas

- `.env` at repo root is gitignored but may exist locally. Never commit it. Use `.env.example` as reference.
- `thoughts/` directory is gitignored — used for local planning docs.
- Node dependencies are not version-locked (installed as `@actual-app/api@${ACTUAL_API_VERSION:-latest}` at first container run). The install is skipped if `/app/node_modules/@actual-app/api` already exists.
- Scripts assume they run from the container working directory. Paths like `/app/`, `/.env`, and `/config/rclone/` are container paths, not host paths.
