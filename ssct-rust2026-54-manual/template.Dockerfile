# Feel free to change the base image to whatever you prefer (Ubuntu, Alpine, etc.)
FROM docker.io/library/debian:trixie-20260824

ARG USERNAME="rust"
ARG USER_UID
ARG USER_GID

# ============================================================================
# Base System Setup (modify package list as needed)
# ============================================================================

# Install packages (add whatever you need)
ARG DEBIAN_FRONTEND="noninteractive"
# basics: ca-certificates curl gnupg locales openssh-server sudo vim
# building: build-essential clang cmake libclang-dev libssh-dev pkg-config
# development: git
# utilities: htop jq rsync tmux tree unzip zip
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg locales openssh-server sudo vim \
        build-essential clang cmake libclang-dev libssh-dev pkg-config \
        git \
        htop jq rsync tmux tree unzip zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Add repos: Docker, Kubernetes (v1.36 to match server), Helm, PostgreSQL
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
        https://download.docker.com/linux/debian trixie stable" \
        | tee /etc/apt/sources.list.d/docker.list
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
        https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
        | tee /etc/apt/sources.list.d/kubernetes.list
RUN curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
        | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/helm.gpg] \
        https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
        | tee /etc/apt/sources.list.d/helm-stable-debian.list
RUN install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] \
        https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
        | tee /etc/apt/sources.list.d/pgdg.list

# Install packages from external repos
# container: docker-ce-cli docker-compose-plugin helm kubectl
# development: postgresql-client-18
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-compose-plugin helm kubectl \
        postgresql-client-18 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# Core Configuration (generally stable, but customizable)
# ============================================================================

# Create user
RUN groupadd -g ${USER_GID} ${USERNAME} \
    && useradd -m -s /bin/bash -u ${USER_UID} -g ${USER_GID} ${USERNAME} \
    && echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}
ENV HOME="/home/${USERNAME}"

# Repair directory permissions
RUN mkdir -p ${HOME}/.config/ ${HOME}/.local/ \
    && chown -R ${USERNAME}:${USERNAME} ${HOME}/.config/ ${HOME}/.local/

# Configure gnupg
RUN echo 'export GPG_TTY=$(tty)' >> ${HOME}/.bashrc

# Configure Docker to use the mapped rootless socket
USER ${USERNAME}
RUN mkdir -p /home/${USERNAME}/.docker/ \
    && echo "export DOCKER_HOST=unix:///home/${USERNAME}/.docker/docker.sock" >> /home/${USERNAME}/.bashrc
USER root

# Configure kubectl
RUN echo 'export KUBECONFIG=${HOME}/.kube/config' >> ${HOME}/.bashrc

# Set timezone and locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && dpkg-reconfigure -f noninteractive tzdata \
    && echo "TZ=Asia/Shanghai" >> /etc/environment \
    && echo "LANG=en_US.UTF-8" >> /etc/environment \
    && echo "LC_ALL=en_US.UTF-8" >> /etc/environment

# ============================================================================
# PERSONAL DEVELOPMENT ENVIRONMENT - Primary customization area
# ============================================================================

USER ${USERNAME}
WORKDIR ${HOME}

# Install additional packages through Nix
# development: fnm
RUN curl -L https://nixos.org/nix/install | sh -s -- --no-daemon \
    && echo '. ${HOME}/.nix-profile/etc/profile.d/nix.sh' >> ${HOME}/.bashrc
ENV PATH="${HOME}/.nix-profile/bin:${PATH}"
RUN . ${HOME}/.nix-profile/etc/profile.d/nix.sh \
    && nix-env -iA \
        nixpkgs.fnm \
    && nix-collect-garbage -d

# Configure fnm and install Node.js (latest) + pnpm
SHELL ["/bin/bash", "-c"]
RUN echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> ${HOME}/.bashrc \
    && eval "$(fnm env --use-on-cd --shell bash)" \
    && fnm install --latest \
    && fnm use $(fnm list | grep latest | sed 's/.*v\([^ ]*\).*/\1/') \
    && npm install -g pnpm
SHELL ["/bin/sh", "-c"]
ENV PNPM_HOME="${HOME}/.local/share/pnpm"
ENV PATH="${PNPM_HOME}/bin:${PATH}"
RUN echo 'export PNPM_HOME="${HOME}/.local/share/pnpm"' >> ${HOME}/.bashrc \
    && echo 'export PATH="${PNPM_HOME}/bin:${PATH}"' >> ${HOME}/.bashrc

# Install Rust toolchain
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="${HOME}/.cargo/bin:${PATH}"

# Install Python miniconda
RUN curl -LO https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    && bash Miniconda3-latest-Linux-x86_64.sh -b \
    && rm Miniconda3-latest-Linux-x86_64.sh
ENV PATH="${HOME}/miniconda3/bin:${PATH}"
RUN conda init \
    && conda config --set auto_activate false \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r \
    && conda config --remove-key channels \
    && conda config --add channels conda-forge
RUN mkdir -p ${HOME}/.local/bin/ \
    && ln -s ${HOME}/miniconda3/bin/python3 ${HOME}/.local/bin/python3
ENV PATH="${HOME}/.local/bin:${HOME}/miniconda3/condabin:${PATH}"
RUN echo 'export PATH="${HOME}/miniconda3/condabin:${PATH}"' >> ${HOME}/.bashrc \
    && echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> ${HOME}/.bashrc

# Install and configure Codex
SHELL ["/bin/bash", "-c"]
RUN eval "$(fnm env --shell bash)" \
    && pnpm add -g @openai/codex
SHELL ["/bin/sh", "-c"]
RUN mkdir -p ${HOME}/.codex/ \
    && rm -rf ${HOME}/.codex/sessions/ \
    && ln -s ${HOME}/workspace/.container/codex/sessions ${HOME}/.codex/sessions \
    && rm -rf ${HOME}/.codex/skills/ \
    && ln -s ${HOME}/workspace/.container/codex/skills ${HOME}/.codex/skills
COPY --chown=${USERNAME}:${USERNAME} codex/config.toml ${HOME}/.codex/config.toml
COPY --chown=${USERNAME}:${USERNAME} codex/auth.json ${HOME}/.codex/auth.json
ENV EDITOR="code"
RUN echo 'export EDITOR="code"' >> ${HOME}/.bashrc

# Try uncomment the following to configure Git identity (and optionally GPG signing):
# USER ${USERNAME}
# RUN git config --global user.name "Your Name" \
#     && git config --global user.email "your.email@example.com"
#     # Optional: enable GPG commit signing (import your key separately)
#     # && git config --global user.signingkey YOUR_GPG_KEY_ID \
#     # && git config --global commit.gpgsign true
# USER root

# ============================================================================
# Container Runtime Configuration (modify only if you know what you're doing)
# ============================================================================

USER root

# Configure SSH
RUN mkdir -p /run/sshd/ \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Run sshd in a loop so it restarts even if it crashes
CMD ["sh", "-c", "while true; do /usr/sbin/sshd -D; sleep 1; done"]
