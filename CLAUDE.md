# CLAUDE.md

## Project

Claude Code Docker Sandbox — a sandboxed development environment for running Claude Code with `bypassPermissions` safely enabled. Provides filesystem isolation via Docker so Claude can execute commands freely without risking the host system.

## Structure

- `Dockerfile` — container image (Ubuntu 24.04 base, pinned digests)
- `docker-compose.yml` — service definition (mounts, env vars, caps, volumes)
- `entrypoint.sh` — runs `post_install.py` (idempotent) on every container start, then `exec "$@"`
- `install.sh` — `devc` CLI helper for managing containers from the host
- `post_install.py` — runs on container start (Claude settings, tmux, git config, ownership fixes)
- `.zshrc` — shell configuration (PATH, aliases, fzf, fnm, history)
- `CLAUDE-user.md` — user-level Claude instructions (copied to `~/.claude/CLAUDE.md` at container start)

## Key Conventions

**Dockerfile**: Pin all base images and tools to exact versions with SHA-256 digests where available. Group related installs, minimize layers. Install user-space tools as `vscode` user, system tools as `root`.

**install.sh**: Strict mode (`set -euo pipefail`). Color-coded output via `log_info`/`log_success`/`log_warn`/`log_error`. All paths must handle spaces. Uses `docker compose` with `-p claude-<dirname>` for per-workspace volume scoping.

**post_install.py**: Each setup concern is its own function. Idempotent — safe to re-run on every start. Logs to stderr with `[post_install]` prefix.

**docker-compose.yml**: Workspace mount via `${WORKSPACE_DIR}` env var (set by `devc`). Named volumes for persistent state. Custom mounts via `mounts.txt` → generated `docker-compose.override.yml`.

## Security Invariants

- `bypassPermissions` is only safe because the container itself is the sandbox
- Host `~/.gitconfig` is mounted read-only — the container uses a local config overlay via `GIT_CONFIG_GLOBAL`
- `entrypoint.sh` is baked into the image (not mounted), so container processes can't modify startup behavior
- No extra capabilities granted — the container has no elevated privileges
