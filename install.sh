#!/bin/bash
set -euo pipefail

# Claude Code Docker Sandbox CLI Helper
# Provides the `devc` command for managing sandbox containers

# Resolve symlinks to get actual script location
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
  cat <<EOF
Usage: devc <command> [options]

Commands:
    .                   Install sandbox template to current directory and start
    up                  Start the sandbox container in current directory
    rebuild             Rebuild the sandbox (preserves auth volumes)
    down                Stop the sandbox container
    shell               Open a shell in the running container
    self-install        Install 'devc' command to ~/.local/bin
    update              Update devc to the latest version
    template [dir]      Copy sandbox template to directory (default: current)
    exec <cmd>          Execute a command in the running container
    upgrade             Upgrade Claude Code to latest version
    mount <host> <cont> Add a mount to the sandbox (recreates container)
    firewall            Block containers from accessing LAN and host ports
    help                Show this help message

Examples:
    devc .                      # Install template and start container
    devc up                     # Start container in current directory
    devc rebuild                # Clean rebuild
    devc shell                  # Open interactive shell
    devc self-install           # Install devc to PATH
    devc update                 # Update to latest version
    devc exec ls -la            # Run command in container
    devc upgrade                # Upgrade Claude Code to latest
    devc mount ~/data /data     # Add mount to container
EOF
}

log_info() {
  echo -e "${BLUE}[devc]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[devc]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[devc]${NC} $1"
}

log_error() {
  echo -e "${RED}[devc]${NC} $1" >&2
}

check_docker_cli() {
  if ! command -v docker &>/dev/null; then
    log_error "docker not found."
    log_info "Install Docker Desktop, OrbStack, or Colima"
    exit 1
  fi
  if ! docker compose version &>/dev/null; then
    log_error "docker compose not available."
    log_info "Update Docker or install the compose plugin"
    exit 1
  fi
  if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q sysbox-runc; then
    log_error "sysbox-runc runtime not found."
    log_info "Install Sysbox: https://github.com/nestybox/sysbox#installation"
    exit 1
  fi
}

get_workspace_folder() {
  local dir="${1:-$(pwd)}"
  (cd "$dir" 2>/dev/null && pwd)
}

get_project_name() {
  local workspace="${1:-$(pwd)}"
  local dirname
  dirname="$(basename "$workspace")"
  # Compose project names: lowercase alphanumeric, hyphens, underscores only
  dirname="${dirname//[^a-zA-Z0-9_-]/-}"
  dirname="${dirname,,}"
  echo "claude-${dirname}"
}

# Run docker compose with the right files, project name, and env vars
compose_cmd() {
  local workspace_folder="$1"
  shift
  local sandbox_dir="$workspace_folder/.claude-sandbox"
  local override_file="$sandbox_dir/docker-compose.override.yml"

  local -a compose_args=(
    -f "$sandbox_dir/docker-compose.yml"
    -p "$(get_project_name "$workspace_folder")"
  )

  [[ -f "$override_file" ]] && compose_args+=(-f "$override_file")

  WORKSPACE_DIR="$workspace_folder" docker compose "${compose_args[@]}" "$@"
}

# Generate docker-compose.override.yml from mounts.txt
generate_override() {
  local sandbox_dir="$1"
  local mounts_file="$sandbox_dir/mounts.txt"
  local override_file="$sandbox_dir/docker-compose.override.yml"

  if [[ ! -f "$mounts_file" ]] || [[ ! -s "$mounts_file" ]]; then
    rm -f "$override_file"
    return
  fi

  {
    echo "services:"
    echo "  sandbox:"
    echo "    volumes:"
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      echo "      - ${line}"
    done <"$mounts_file"
  } >"$override_file"
}

# Extract custom mounts from mounts.txt to a temp file for preservation
extract_mounts_to_file() {
  local sandbox_dir="$1"
  local mounts_file="$sandbox_dir/mounts.txt"

  [[ -f "$mounts_file" ]] || return 0
  [[ -s "$mounts_file" ]] || return 0

  local temp_file
  temp_file=$(mktemp)
  cp "$mounts_file" "$temp_file"
  echo "$temp_file"
}

cmd_template() {
  local target_dir="${1:-.}"
  target_dir="$(cd "$target_dir" 2>/dev/null && pwd)" || {
    log_error "Directory does not exist: $1"
    exit 1
  }

  local sandbox_dir="$target_dir/.claude-sandbox"
  local preserved_mounts=""

  if [[ -d "$sandbox_dir" ]]; then
    log_warn "Sandbox config already exists at $sandbox_dir"
    read -p "Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Aborted."
      exit 0
    fi

    # Preserve custom mounts before overwriting
    preserved_mounts=$(extract_mounts_to_file "$sandbox_dir")
    if [[ -n "$preserved_mounts" ]]; then
      log_info "Preserving custom mounts..."
    fi
  fi

  mkdir -p "$sandbox_dir"

  # Copy template files
  cp "$SCRIPT_DIR/Dockerfile" "$sandbox_dir/"
  cp "$SCRIPT_DIR/docker-compose.yml" "$sandbox_dir/"
  cp "$SCRIPT_DIR/entrypoint.sh" "$sandbox_dir/"
  cp "$SCRIPT_DIR/post_install.py" "$sandbox_dir/"
  cp "$SCRIPT_DIR/.zshrc" "$sandbox_dir/"
  cp "$SCRIPT_DIR/CLAUDE-user.md" "$sandbox_dir/"
  cp -r "$SCRIPT_DIR/hooks" "$sandbox_dir/"

  # Restore preserved mounts
  if [[ -n "$preserved_mounts" ]]; then
    cp "$preserved_mounts" "$sandbox_dir/mounts.txt"
    rm -f "$preserved_mounts"
    generate_override "$sandbox_dir"
    log_info "Custom mounts restored"
  fi

  log_success "Template installed to $sandbox_dir"
}

cmd_up() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder "${1:-}")"

  check_docker_cli

  # Ensure files exist for read-only bind mounts
  test -f "$HOME/.gitconfig" || touch "$HOME/.gitconfig"
  test -f "$workspace_folder/.gitattributes" || touch "$workspace_folder/.gitattributes"

  log_info "Starting sandbox in $workspace_folder..."

  compose_cmd "$workspace_folder" up -d
  log_success "Sandbox started"
}

cmd_firewall() {
  if [[ "$(id -u)" -ne 0 ]]; then
    log_error "Firewall requires root. Run: sudo devc firewall"
    exit 1
  fi

  for cmd in iptables netfilter-persistent; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "$cmd not found. Install with: apt install iptables-persistent"
      exit 1
    fi
  done

  local rules_changed=false

  # DOCKER-USER: block forwarded traffic to LAN
  for rule in "-d 10.0.0.0/8 -j DROP" "-d 192.168.0.0/16 -j DROP"; do
    if ! iptables -C DOCKER-USER $rule 2>/dev/null; then
      iptables -A DOCKER-USER $rule
      rules_changed=true
    fi
  done

  # INPUT: block containers from reaching host ports via bridge interfaces
  for rule in "-i docker0 -j DROP" "-i br-+ -j DROP"; do
    if ! iptables -C INPUT $rule 2>/dev/null; then
      iptables -A INPUT $rule
      rules_changed=true
    fi
  done

  if [[ "$rules_changed" == "true" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    for f in /etc/iptables/rules.v4 /etc/iptables/rules.v6; do
      [[ -f "$f" ]] && cp "$f" "${f}.${ts}.bak" && log_info "Backed up ${f}.${ts}.bak"
    done
    netfilter-persistent save
    log_success "Firewall rules applied and saved"
  else
    log_success "Firewall rules already in place"
  fi
}

cmd_rebuild() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder "${1:-}")"

  check_docker_cli

  # Ensure files exist for read-only bind mounts
  test -f "$HOME/.gitconfig" || touch "$HOME/.gitconfig"
  test -f "$workspace_folder/.gitattributes" || touch "$workspace_folder/.gitattributes"

  log_info "Rebuilding sandbox in $workspace_folder..."

  compose_cmd "$workspace_folder" build
  compose_cmd "$workspace_folder" up -d --force-recreate
  log_success "Sandbox rebuilt"
}

cmd_down() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder "${1:-}")"

  check_docker_cli
  log_info "Stopping sandbox..."

  compose_cmd "$workspace_folder" down
  log_success "Sandbox stopped"
}

cmd_shell() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder)"

  check_docker_cli
  log_info "Opening shell in sandbox..."

  compose_cmd "$workspace_folder" exec sandbox zsh
}

cmd_exec() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder)"

  check_docker_cli
  compose_cmd "$workspace_folder" exec sandbox "$@"
}

cmd_upgrade() {
  local workspace_folder
  workspace_folder="$(get_workspace_folder)"

  check_docker_cli
  log_info "Upgrading Claude Code..."

  compose_cmd "$workspace_folder" exec sandbox claude update

  log_success "Claude Code upgraded"
}

cmd_mount() {
  local host_path="${1:-}"
  local container_path="${2:-}"
  local readonly="false"

  if [[ -z "$host_path" ]] || [[ -z "$container_path" ]]; then
    log_error "Usage: devc mount <host_path> <container_path> [--readonly]"
    exit 1
  fi

  [[ "${3:-}" == "--readonly" ]] && readonly="true"

  # Expand and validate host path
  host_path="$(cd "$host_path" 2>/dev/null && pwd)" || {
    log_error "Host path does not exist: $1"
    exit 1
  }

  local workspace_folder
  workspace_folder="$(get_workspace_folder)"
  local sandbox_dir="$workspace_folder/.claude-sandbox"
  local mounts_file="$sandbox_dir/mounts.txt"

  if [[ ! -f "$sandbox_dir/docker-compose.yml" ]]; then
    log_error "No sandbox config found. Run 'devc template' first."
    exit 1
  fi

  check_docker_cli

  # Build mount string
  local mount_str="${host_path}:${container_path}"
  [[ "$readonly" == "true" ]] && mount_str="${mount_str}:ro"

  # Remove any existing mount for the same container path, then add new one
  if [[ -f "$mounts_file" ]]; then
    local temp
    temp=$(mktemp)
    grep -v ":${container_path}\(:\|$\)" "$mounts_file" >"$temp" 2>/dev/null || true
    mv "$temp" "$mounts_file"
  fi
  echo "$mount_str" >>"$mounts_file"

  # Regenerate override and recreate container
  generate_override "$sandbox_dir"

  log_info "Adding mount: $host_path -> $container_path"
  log_info "Recreating container with new mount..."
  compose_cmd "$workspace_folder" up -d --force-recreate

  log_success "Mount added: $host_path -> $container_path"
}

cmd_self_install() {
  local install_dir="$HOME/.local/bin"
  local install_path="$install_dir/devc"

  mkdir -p "$install_dir"

  # Create a symlink to the original script
  ln -sf "$SCRIPT_DIR/$SCRIPT_NAME" "$install_path"

  log_success "Installed 'devc' to $install_path"

  # Check if in PATH
  if [[ ":$PATH:" != *":$install_dir:"* ]]; then
    log_warn "$install_dir is not in your PATH"
    log_info "Add this to your shell profile:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

cmd_update() {
  log_info "Updating devc..."

  if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    log_error "Not a git repository: $SCRIPT_DIR"
    log_info "Re-clone with: rm -rf ~/.claude-sandbox && git clone https://github.com/trailofbits/claude-code-sandbox ~/.claude-sandbox"
    exit 1
  fi

  local before_sha after_sha
  before_sha=$(git -C "$SCRIPT_DIR" rev-parse HEAD)

  if ! git -C "$SCRIPT_DIR" pull --ff-only; then
    log_error "Update failed. Try: cd $SCRIPT_DIR && git pull"
    exit 1
  fi

  after_sha=$(git -C "$SCRIPT_DIR" rev-parse HEAD)

  if [[ "$before_sha" == "$after_sha" ]]; then
    log_success "Already up to date"
  else
    log_success "Updated from ${before_sha:0:7} to ${after_sha:0:7}"
  fi
}

cmd_dot() {
  # Install template and start container in one command
  cmd_template "."
  cmd_up "."
}

# Main command dispatcher
main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  local command="$1"
  shift

  case "$command" in
  .)
    cmd_dot
    ;;
  up)
    cmd_up "$@"
    ;;
  rebuild)
    cmd_rebuild "$@"
    ;;
  down)
    cmd_down "$@"
    ;;
  shell)
    cmd_shell
    ;;
  exec)
    [[ "${1:-}" == "--" ]] && shift
    cmd_exec "$@"
    ;;
  upgrade)
    cmd_upgrade
    ;;
  mount)
    cmd_mount "$@"
    ;;
  self-install)
    cmd_self_install
    ;;
  update)
    cmd_update
    ;;
  template)
    cmd_template "$@"
    ;;
  firewall)
    cmd_firewall
    ;;
  help | --help | -h)
    print_usage
    ;;
  *)
    log_error "Unknown command: $command"
    print_usage
    exit 1
    ;;
  esac
}

main "$@"
