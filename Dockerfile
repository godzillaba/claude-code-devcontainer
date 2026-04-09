# Claude Code Docker Sandbox
ARG UV_VERSION=0.10.0
FROM ghcr.io/astral-sh/uv:${UV_VERSION}@sha256:78a7ff97cd27b7124a5f3c2aefe146170793c56a1e03321dd31a289f6d82a04f AS uv
FROM ubuntu:24.04@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9

ARG TZ
ENV TZ="$TZ"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  curl \
  sudo \
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
  unzip \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create vscode user (remove default ubuntu user that occupies UID/GID 1000)
RUN userdel -r ubuntu 2>/dev/null; \
  groupdel ubuntu 2>/dev/null; \
  groupadd --gid 1000 vscode && \
  useradd --uid 1000 --gid 1000 -m -s /bin/zsh vscode && \
  echo 'vscode ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/vscode && \
  chmod 0440 /etc/sudoers.d/vscode

# Install GitHub CLI via apt repo
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
  apt-get update && apt-get install -y --no-install-recommends gh && \
  apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Docker CE (Docker-in-Docker)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list && \
  apt-get update && apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin && \
  apt-get clean && rm -rf /var/lib/apt/lists/* && \
  usermod -aG docker vscode

# Install git-delta
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  curl -fsSL "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" -o /tmp/git-delta.deb && \
  dpkg -i /tmp/git-delta.deb && \
  rm /tmp/git-delta.deb

# Install uv (Python package manager) via multi-stage copy
COPY --from=uv /uv /usr/local/bin/uv

# Install fzf from GitHub releases (newer than apt, includes built-in shell integration)
ARG FZF_VERSION=0.67.0
RUN ARCH=$(dpkg --print-architecture) && \
  case "${ARCH}" in \
    amd64) FZF_ARCH="linux_amd64" ;; \
    arm64) FZF_ARCH="linux_arm64" ;; \
    *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
  esac && \
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-${FZF_ARCH}.tar.gz" | tar -xz -C /usr/local/bin

# Create shared directories that need root ownership initially
RUN mkdir -p /commandhistory /workspace /opt && \
  touch /commandhistory/.bash_history /commandhistory/.zsh_history && \
  chown -R vscode:vscode /commandhistory /workspace /opt

# Set environment variables
ENV DOCKER_SANDBOX=true
ENV SHELL=/bin/zsh
ENV TERM=xterm-256color
ENV EDITOR=nano
ENV VISUAL=nano

WORKDIR /workspace
USER vscode

# Create user directories (no chown needed — already running as vscode)
RUN mkdir -p ~/.claude

# Set PATH early so claude and other user-installed binaries are available
ENV PATH="/home/vscode/.local/bin:$PATH"

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Python 3.13 via uv (fast binary download, not source compilation)
RUN uv python install 3.13 --default

# Install ast-grep (AST-based code search)
RUN uv tool install ast-grep-cli

# Install fnm (Fast Node Manager) and Node 22
ARG NODE_VERSION=22
ENV FNM_DIR="/home/vscode/.fnm"
RUN curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$FNM_DIR" --skip-shell && \
  export PATH="$FNM_DIR:$PATH" && \
  eval "$(fnm env)" && \
  fnm install ${NODE_VERSION} && \
  fnm default ${NODE_VERSION} && \
  corepack enable

# Install Oh My Zsh
ARG ZSH_IN_DOCKER_VERSION=1.2.1
RUN sh -c "$(curl -fsSL https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -p git \
  -x


# Install Foundry (forge, cast, anvil, chisel)
ENV PATH="/home/vscode/.foundry/bin:$PATH"
RUN curl -L https://foundry.paradigm.xyz | bash && foundryup

# Install Go (needs root for /usr/local)
USER root
ARG GO_VERSION=1.26.0
RUN ARCH=$(dpkg --print-architecture) && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -xz -C /usr/local

# Install Solidity compiler (solc)
ARG SOLC_VERSION=0.8.34
RUN curl -fsSL "https://github.com/ethereum/solidity/releases/download/v${SOLC_VERSION}/solc-static-linux" -o /usr/local/bin/solc && \
  chmod +x /usr/local/bin/solc

# Install Certora Gambit (Solidity mutation testing)
ARG GAMBIT_VERSION=1.0.6
RUN curl -fsSL "https://github.com/Certora/gambit/releases/download/v${GAMBIT_VERSION}/gambit-linux-v${GAMBIT_VERSION}" -o /usr/local/bin/gambit && \
  chmod +x /usr/local/bin/gambit
USER vscode

# Add to PATH
ENV GOPATH="/home/vscode/go"
ENV PATH="/home/vscode/go/bin:/usr/local/go/bin:$PATH"

# Copy zsh configuration
COPY --chown=vscode:vscode .zshrc /home/vscode/.zshrc.custom

# Append custom zshrc to the main one
RUN echo 'source ~/.zshrc.custom' >> /home/vscode/.zshrc

# Clone pashov/skills (custom Claude Code slash commands)
RUN git clone https://github.com/pashov/skills.git /opt/pashov-skills

# Clone nemesis-auditor skills (feynman, nemesis, state-inconsistency auditors)
RUN git clone https://github.com/0xiehnnkta/nemesis-auditor.git /opt/nemesis-auditor && \
  git -C /opt/nemesis-auditor checkout 75cecc6

# Copy post_install script and user-level CLAUDE.md
COPY --chown=vscode:vscode post_install.py /opt/post_install.py
COPY --chown=vscode:vscode CLAUDE-user.md /opt/CLAUDE-user.md
COPY --chown=vscode:vscode hooks/ /opt/hooks/

# Entrypoint runs post_install.py (idempotent) on every container start
COPY --chown=vscode:vscode entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
