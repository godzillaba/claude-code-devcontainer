# CLAUDE.md

## Project

Claude Code Devcontainer — a sandboxed development environment for running Claude Code with `bypassPermissions` safely enabled. Provides filesystem isolation via Docker so Claude can execute commands freely without risking the host system.

## Structure

- `Dockerfile` — multi-stage container image (Ubuntu 24.04 base, pinned digests)
- `devcontainer.json` — Dev Containers spec (mounts, env vars, extensions, features)
- `install.sh` — `devc` CLI helper for managing containers from the host
- `post_install.py` — runs on container creation (Claude settings, tmux, git config, ownership fixes)
- `.zshrc` — shell configuration (PATH, aliases, fzf, fnm, history)
- `CLAUDE-user.md` — user-level Claude instructions (copied to `~/.claude/CLAUDE.md` at container creation)

## Key Conventions

**Dockerfile**: Pin all base images and tools to exact versions with SHA-256 digests where available. Group related installs, minimize layers. Install user-space tools as `vscode` user, system tools as `root`.

**install.sh**: Strict mode (`set -euo pipefail`). Color-coded output via `log_info`/`log_success`/`log_warn`/`log_error`. All paths must handle spaces. Security-critical: `check_no_sys_admin` rejects SYS_ADMIN capability to preserve the read-only `.devcontainer/` mount.

**post_install.py**: Each setup concern is its own function. Idempotent — safe to re-run. Logs to stderr with `[post_install]` prefix.

**devcontainer.json**: Default mounts use `${devcontainerId}` for per-container volumes. Custom mounts added via `devc mount` are preserved across `devc template` updates.

## Security Invariants

- `.devcontainer/` is mounted read-only inside the container to prevent a compromised process from injecting malicious config that executes on the host during rebuild
- SYS_ADMIN capability is never allowed (it would enable remounting read-write)
- `bypassPermissions` is only safe because the container itself is the sandbox
- Host `~/.gitconfig` is mounted read-only — the container uses a local config overlay via `GIT_CONFIG_GLOBAL`
