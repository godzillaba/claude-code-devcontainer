# Claude Code sbx template.
#
# Extends the Docker Sandbox `claude-code-docker` base (Claude Code + in-VM Docker
# Engine) with the Arbitrum/Solidity audit toolchain, shell + Claude config, skills,
# and plugins. Everything is baked at build time; there is no kit.
#
# The base already provides `claude`, `gh`, Docker, git, and curl, so those are not
# reinstalled. The base user is `agent` (uid 1000, home /home/agent).

ARG UV_VERSION=0.10.0
FROM ghcr.io/astral-sh/uv:${UV_VERSION}@sha256:78a7ff97cd27b7124a5f3c2aefe146170793c56a1e03321dd31a289f6d82a04f AS uv

# Compile esk (Ethereum Swiss Army Knife) into a standalone binary via `bun --compile`.
ARG ESK_COMMIT=e2bced08a6588d6f4d0246457238a5450bcf84fc
FROM oven/bun:1.3.13@sha256:87416c977a612a204eb54ab9f3927023c2a3c971f4f345a01da08ea6262ae30e AS esk-builder
ARG ESK_COMMIT
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/* && \
  git clone https://github.com/godzillaba/eth-cli /tmp/esk && \
  cd /tmp/esk && \
  git checkout ${ESK_COMMIT} && \
  bun install --frozen-lockfile && \
  bun build src/index.ts --compile --outfile=/esk

# Compile gambit (Certora Solidity mutation testing) from source so the binary matches the build
# platform's architecture. Certora only publishes x86-64 Linux and macOS release binaries, so the
# prebuilt download fails with "Exec format error" on arm64 (Apple Silicon).
FROM rust:1-slim@sha256:6abf73f05806f36362d0ff2722f2250c6153398831edd0455e0e0baa1f78ecc7 AS gambit-builder
ARG GAMBIT_VERSION=1.0.6
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/* && \
  cargo install --git https://github.com/Certora/gambit --tag v${GAMBIT_VERSION} --root /out

# Base: Docker Sandbox Claude Code image with in-VM Docker Engine.
# TODO: pin to an immutable digest (FROM ...@sha256:...) once resolved on the host.
FROM docker/sandbox-templates:claude-code-docker

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# System packages (root)
# ---------------------------------------------------------------------------
USER root

ARG TZ=UTC
ENV TZ="$TZ"

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  gnupg2 \
  # headless browser stuff
  libxcomposite1 libxcursor1 libxdamage1 libxfixes3 libgtk-3-0t64 libpangocairo-1.0-0 libpango-1.0-0 libatk1.0-0t64 libcairo-gobject2 libgdk-pixbuf-2.0-0 libasound2t64 \
  libreoffice-writer \
  texlive-latex-base \
  # Sandboxing support for Claude Code
  bubblewrap \
  socat \
  # Modern CLI tools
  fd-find \
  ripgrep \
  tmux \
  zsh \
  # Build tools
  build-essential \
  # Utilities
  jq \
  nano \
  trash-cli \
  unzip \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# git-delta
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  curl -fsSL "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" -o /tmp/git-delta.deb && \
  dpkg -i /tmp/git-delta.deb && \
  rm /tmp/git-delta.deb

# uv (Python package manager) via multi-stage copy
COPY --from=uv /uv /usr/local/bin/uv

# fzf from GitHub releases (newer than apt, includes built-in shell integration)
ARG FZF_VERSION=0.67.0
RUN ARCH=$(dpkg --print-architecture) && \
  case "${ARCH}" in \
    amd64) FZF_ARCH="linux_amd64" ;; \
    arm64) FZF_ARCH="linux_arm64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
  esac && \
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-${FZF_ARCH}.tar.gz" | tar -xz -C /usr/local/bin

# Go
ARG GO_VERSION=1.26.0
RUN ARCH=$(dpkg --print-architecture) && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -xz -C /usr/local

# Solidity compiler (solc) — pick the arch-appropriate static binary (the plain
# `solc-static-linux` asset is x86-64 only and fails with "Exec format error" on arm64).
ARG SOLC_VERSION=0.8.34
RUN ARCH=$(dpkg --print-architecture) && \
  case "${ARCH}" in \
    amd64) SOLC_ASSET="solc-static-linux" ;; \
    arm64) SOLC_ASSET="solc-static-linux-arm" ;; \
    *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
  esac && \
  curl -fsSL "https://github.com/ethereum/solidity/releases/download/v${SOLC_VERSION}/${SOLC_ASSET}" -o /usr/local/bin/solc && \
  chmod +x /usr/local/bin/solc

# Certora Gambit (Solidity mutation testing) — built from source in the gambit-builder stage
COPY --from=gambit-builder /out/bin/gambit /usr/local/bin/gambit

# esk (Ethereum Swiss Army Knife) — built in the esk-builder stage
COPY --from=esk-builder /esk /usr/local/bin/esk
RUN chmod +x /usr/local/bin/esk

# Reference data
COPY arbitrum-addresses.env /opt/arbitrum-addresses.env

# RPC endpoints + Etherscan key, baked verbatim from template/.env (gitignored; required at
# build). Sourced into the env: non-interactive bash (the Bash tool) reads it via
# BASH_ENV=/etc/sandbox-persistent.sh; interactive zsh loads it from .zshrc. `set -a` exports
# the quoted KEY="value" lines.
COPY .env /opt/rpc.env
RUN touch /etc/sandbox-persistent.sh \
 && printf 'set -a; [ -f /opt/rpc.env ] && . /opt/rpc.env; set +a\n' >> /etc/sandbox-persistent.sh \
 && chown agent:agent /etc/sandbox-persistent.sh

# Default the agent user's login shell to zsh
RUN chsh -s /bin/zsh agent

# Environment
ENV SHELL=/bin/zsh \
    EDITOR=nano \
    VISUAL=nano \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    NODE_OPTIONS=--max-old-space-size=4096 \
    UV_LINK_MODE=copy \
    NPM_CONFIG_IGNORE_SCRIPTS=true \
    NPM_CONFIG_AUDIT=true \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_SAVE_EXACT=true \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_MINIMUM_RELEASE_AGE=1440 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ---------------------------------------------------------------------------
# User-space tools (agent)
# ---------------------------------------------------------------------------
USER agent
WORKDIR /home/agent

ENV GOPATH="/home/agent/go"
ENV FNM_DIR="/home/agent/.fnm"
ENV PATH="/home/agent/.local/bin:/home/agent/.foundry/bin:/home/agent/go/bin:/usr/local/go/bin:/home/agent/.fnm:$PATH"

# Python 3.13 via uv (fast binary download, not source compilation)
RUN uv python install 3.13 --default

# ast-grep (AST-based code search)
RUN uv tool install ast-grep-cli

# fnm (Fast Node Manager) and Node
ARG NODE_VERSION=22
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell && \
  export PATH="$FNM_DIR:$PATH" && \
  eval "$(fnm env)" && \
  fnm install ${NODE_VERSION} && \
  fnm default ${NODE_VERSION} && \
  corepack enable

# Oh My Zsh
ARG ZSH_IN_DOCKER_VERSION=1.2.1
RUN sh -c "$(curl -fsSL https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -x

# Foundry (forge, cast, anvil, chisel)
RUN curl -L https://foundry.paradigm.xyz | bash && foundryup

# Shell configuration
COPY --chown=agent:agent .zshrc /home/agent/.zshrc.custom
RUN echo 'source ~/.zshrc.custom' >> /home/agent/.zshrc

# tmux, git config, and global gitignore.
# gitconfig goes to the XDG global path so it does not shadow any user identity
# that sbx or the user sets in ~/.gitconfig.
COPY --chown=agent:agent tmux.conf /home/agent/.tmux.conf
RUN mkdir -p /home/agent/.config/git
COPY --chown=agent:agent gitconfig /home/agent/.config/git/config
COPY --chown=agent:agent gitignore_global /home/agent/.gitignore_global

# User-level Claude memory + hooks
RUN mkdir -p /home/agent/.claude/hooks
COPY --chown=agent:agent CLAUDE.md /home/agent/.claude/CLAUDE.md
COPY --chown=agent:agent hooks/ /home/agent/.claude/hooks/
RUN chmod +x /home/agent/.claude/hooks/*.bash

# Skills: pashov solidity-auditor (as a slash command) + nemesis-auditor skills
RUN git clone https://github.com/pashov/skills.git /tmp/pashov-skills && \
  mkdir -p /home/agent/.claude/commands && \
  cp -r /tmp/pashov-skills/solidity-auditor /home/agent/.claude/commands/solidity-auditor && \
  rm -rf /tmp/pashov-skills

RUN git clone https://github.com/0xiehnnkta/nemesis-auditor.git /tmp/nemesis && \
  git -C /tmp/nemesis checkout 75cecc6 && \
  mkdir -p /home/agent/.claude/skills && \
  cp -r /tmp/nemesis/.claude/skills/. /home/agent/.claude/skills/ && \
  rm -rf /tmp/nemesis

# Claude Code plugins (marketplaces + plugins). Baked at build time; per-item
# failures are non-fatal so a single bad ref does not break the image build.
RUN for m in \
      anthropics/skills \
      trailofbits/skills \
      trailofbits/skills-curated \
      godzillaba/my-plugins \
      ast-grep/agent-skill \
      ayghri/i-have-adhd; do \
    claude plugin marketplace add "$m" || echo "WARN: marketplace add failed: $m" >&2; \
  done; \
  for p in \
      scv-scan@skills-curated \
      building-secure-contracts@trailofbits \
      entry-point-analyzer@trailofbits \
      property-based-testing@trailofbits \
      differential-review@trailofbits \
      mutest@godzillaba-plugins \
      nitro-testnode@godzillaba-plugins \
      company-search@godzillaba-plugins \
      ast-grep \
      i-have-adhd@i-have-adhd; do \
    claude plugin install "$p" || echo "WARN: plugin install failed: $p" >&2; \
  done

# Always-on ADHD output shaping: the i-have-adhd plugin's SessionStart hook
# injects its ruleset whenever this flag file exists.
RUN touch /home/agent/.claude/.i-have-adhd-always

# Claude settings for sandboxes. A wrapper injects via --settings, which does merge. sbx execs
# `claude` by PATH lookup using the image ENV, so the wrapper dir goes first.
# Placed after the plugin installs so the wrapper is inert during the build.
COPY claude-settings.json /etc/claude-code/claude-settings.json
# sbx overwrites ~/.claude/settings.json at sandbox creation with the host's copy,
# wiping the enabledPlugins map the plugin installs wrote there. Carry it into the
# wrapper-injected settings so plugins stay enabled.
USER root
RUN jq -s '.[0] + {enabledPlugins: (.[1].enabledPlugins // {})}' \
      /etc/claude-code/claude-settings.json /home/agent/.claude/settings.json \
      > /tmp/cs.json && mv /tmp/cs.json /etc/claude-code/claude-settings.json
USER agent
COPY claude-wrapper /opt/claude-wrapper/claude
ENV PATH="/opt/claude-wrapper:${PATH}"

# Restore the base image's working directory (where sbx mounts the workspace and
# launches the agent). Do NOT override ENTRYPOINT/CMD: the base already runs
# `tini -- claude --dangerously-skip-permissions`.
WORKDIR /home/agent/workspace
