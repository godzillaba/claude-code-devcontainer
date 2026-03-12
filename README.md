# Claude Code Docker Sandbox

A sandboxed development environment for running Claude Code with `bypassPermissions` safely enabled. Built at [Trail of Bits](https://www.trailofbits.com/) for security audit workflows.

## Why Use This?

Running Claude with `bypassPermissions` on your host machine is risky—it can execute any command without confirmation. This Docker sandbox provides **filesystem isolation** so you get the productivity benefits of unrestricted Claude without risking your host system.

**Designed for:**

- **Security audits**: Review client code without risking your host
- **Untrusted repositories**: Explore unknown codebases safely
- **Experimental work**: Let Claude modify code freely in isolation
- **Multi-repo engagements**: Work on multiple related repositories

## Prerequisites

- **Docker** with compose plugin (one of):
  - [Docker Desktop](https://docker.com/products/docker-desktop) - ensure it's running
  - [OrbStack](https://orbstack.dev/)
  - [Colima](https://github.com/abiosoft/colima): `brew install colima docker docker-compose && colima start`

- **One-time install:**

  ```bash
  git clone https://github.com/trailofbits/claude-code-sandbox ~/.claude-sandbox
  ~/.claude-sandbox/install.sh self-install
  ```

<details>
<summary><strong>Optimizing Colima for Apple Silicon</strong></summary>

Colima's defaults (QEMU + sshfs) are conservative. For better performance:

```bash
# Stop and delete current VM (removes containers/images)
colima stop && colima delete

# Start with optimized settings
colima start \
  --cpu 4 \
  --memory 8 \
  --disk 100 \
  --vm-type vz \
  --vz-rosetta \
  --mount-type virtiofs
```

Adjust `--cpu` and `--memory` based on your Mac (e.g., 6/16 for Pro, 8/32 for Max).

| Option | Benefit |
|--------|---------|
| `--vm-type vz` | Apple Virtualization.framework (faster than QEMU) |
| `--mount-type virtiofs` | 5-10x faster file I/O than sshfs |
| `--vz-rosetta` | Run x86 containers via Rosetta |

Verify with `colima status` - should show "macOS Virtualization.Framework" and "virtiofs".

</details>

## Quick Start

Choose the pattern that fits your workflow:

### Pattern A: Per-Project Container (Isolated)

Each project gets its own container with independent volumes. Best for one-off reviews, untrusted repos, or when you need isolation between projects.

```bash
git clone <untrusted-repo>
cd untrusted-repo
devc .          # Installs template + starts container
devc shell      # Opens shell in container
```

### Pattern B: Shared Workspace Container (Grouped)

A parent directory contains the sandbox config, and you clone multiple repos inside. Shared volumes across all repos. Best for client engagements, related repositories, or ongoing work.

```bash
# Create workspace for a client engagement
mkdir -p ~/sandbox/client-name
cd ~/sandbox/client-name
devc .          # Install template + start container
devc shell      # Opens shell in container

# Inside container:
git clone <client-repo-1>
git clone <client-repo-2>
cd client-repo-1
claude          # Ready to work
```

## CLI Reference

```
devc .              Install template + start container in current directory
devc up             Start the sandbox container
devc rebuild        Rebuild container (preserves persistent volumes)
devc down           Stop the container
devc shell          Open zsh shell in container
devc exec CMD       Execute command inside the container
devc upgrade        Upgrade Claude Code in the container
devc mount SRC DST  Add a bind mount (host -> container)
devc template DIR   Copy sandbox files to directory
devc self-install   Install devc to ~/.local/bin
devc update         Update devc to latest version
```

## File Sharing

### `devc mount`

To make a host directory available inside the container:

```bash
devc mount ~/drop /drop           # Read-write
devc mount ~/secrets /secrets --readonly
```

This adds a bind mount and recreates the container. Existing mounts are preserved across `devc template` updates.

**Tip:** A shared "drop folder" is useful for passing files in without mounting your entire home directory.

> **Security note:** Avoid mounting large host directories (e.g., `$HOME`). Every mounted path is writable from inside the container unless `--readonly` is specified, which undermines the filesystem isolation this project provides.

### VS Code / Cursor

You can attach VS Code to the running container using the Docker extension, then drag files into the Explorer panel.

## Security Model

This sandbox provides **filesystem isolation** but not complete sandboxing.

**Sandboxed:** Filesystem (host files inaccessible), processes (isolated from host), package installations (stay in container)

**Not sandboxed:** Network (full outbound by default), git identity (`~/.gitconfig` mounted read-only), Docker socket (not mounted by default)

The container auto-configures `bypassPermissions` mode—Claude runs commands without confirmation. This would be risky on a host machine, but the container itself is the sandbox.

`entrypoint.sh` is baked into the image (not mounted from the host), so a compromised container process cannot modify startup behavior.

## Container Details

| Component | Details |
|-----------|---------|
| Base | Ubuntu 24.04, Node.js 22, Python 3.13 + uv, zsh |
| User | `vscode` (UID 1000, passwordless sudo), working dir `/workspace` |
| Tools | `rg`, `fd`, `tmux`, `fzf`, `delta`, `gh` |
| Volumes (survive rebuilds) | Command history (`/commandhistory`), Claude config (`~/.claude`), GitHub CLI auth (`~/.config/gh`) |
| Host mounts | `~/.gitconfig` (read-only) |
| Auto-configured | [anthropics](https://github.com/anthropics/claude-code-plugins) + [trailofbits](https://github.com/trailofbits/claude-code-plugins) skills, git-delta |

Volumes are scoped per workspace via docker compose project names (`claude-<dirname>`), so multiple sandboxes have independent state. Host `~/.gitconfig` is mounted read-only for git identity.

## Troubleshooting

### Container won't start

1. Check Docker is running: `docker info`
2. Try rebuilding: `devc rebuild`
3. Check logs: `docker compose logs`

### GitHub CLI auth not persisting

The gh volume may need ownership fix:

```bash
sudo chown -R $(id -u):$(id -g) ~/.config/gh
```

### Python/uv not working

Python is managed via uv:

```bash
uv run script.py              # Run a script
uv add package                # Add project dependency
uv run --with requests py.py  # Ad-hoc dependency
```

## Development

Build the image manually:

```bash
cd .claude-sandbox
docker compose build
```

Test the container:

```bash
cd .claude-sandbox
WORKSPACE_DIR=$(pwd)/.. docker compose -p claude-test up -d
docker compose -p claude-test exec sandbox zsh
```
