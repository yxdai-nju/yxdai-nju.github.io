# 基础镜像，可以换成 Ubuntu、Alpine 等
FROM docker.io/library/debian:trixie-20260824

ARG USERNAME="rust"
ARG USER_UID
ARG USER_GID

# ============================================================================
# 系统软件包/常用软件包
# ============================================================================

ARG DEBIAN_FRONTEND="noninteractive"
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg locales openssh-server sudo vim \
        build-essential clang cmake libclang-dev libssh-dev pkg-config \
        git \
        htop jq rsync tmux tree unzip zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 添加 Docker 仓库
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
        https://download.docker.com/linux/debian trixie stable" \
        | tee /etc/apt/sources.list.d/docker.list

# 添加 Kubernetes 仓库（v1.36，与服务器版本一致）
RUN curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
        https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
        | tee /etc/apt/sources.list.d/kubernetes.list

# 添加 Helm 仓库
RUN curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
        | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/helm.gpg] \
        https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
        | tee /etc/apt/sources.list.d/helm-stable-debian.list

# 添加 PostgreSQL 仓库
RUN install -d /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] \
        https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
        | tee /etc/apt/sources.list.d/pgdg.list

# 安装容器和数据库工具
RUN apt-get update \
    && apt-get install -y \
        docker-ce-cli docker-compose-plugin helm kubectl \
        postgresql-client-18 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# 用户和系统配置（一般不需要修改）
# ============================================================================

RUN groupadd -g ${USER_GID} ${USERNAME} \
    && useradd -m -s /bin/bash -u ${USER_UID} -g ${USER_GID} ${USERNAME} \
    && echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}
ENV HOME="/home/${USERNAME}"

RUN mkdir -p ${HOME}/.config/ ${HOME}/.local/ \
    && chown -R ${USERNAME}:${USERNAME} ${HOME}/.config/ ${HOME}/.local/

RUN echo 'export GPG_TTY=$(tty)' >> ${HOME}/.bashrc

USER ${USERNAME}
RUN mkdir -p /home/${USERNAME}/.docker/ \
    && echo "export DOCKER_HOST=unix:///home/${USERNAME}/.docker/docker.sock" >> /home/${USERNAME}/.bashrc
USER root

RUN echo 'export KUBECONFIG=${HOME}/.kube/config' >> ${HOME}/.bashrc

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && dpkg-reconfigure -f noninteractive tzdata \
    && echo "TZ=Asia/Shanghai" >> /etc/environment \
    && echo "LANG=en_US.UTF-8" >> /etc/environment \
    && echo "LC_ALL=en_US.UTF-8" >> /etc/environment

# ============================================================================
# 个人开发环境（主要在这里定制）
# ============================================================================

# 安装自己需要的额外软件包
# RUN apt-get update \
#     && apt-get install -y \
#         packages-that-you-need \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/*

USER ${USERNAME}
WORKDIR ${HOME}

# 通过 Nix 安装自己需要的额外软件包（可选，用于安装一些 apt 未提供的软件包）
# 这里安装 fnm 作为示例
RUN curl -L https://nixos.org/nix/install | sh -s -- --no-daemon \
    && echo '. ${HOME}/.nix-profile/etc/profile.d/nix.sh' >> ${HOME}/.bashrc
ENV PATH="${HOME}/.nix-profile/bin:${PATH}"
RUN . ${HOME}/.nix-profile/etc/profile.d/nix.sh \
    && nix-env -iA \
        nixpkgs.fnm \
    && nix-collect-garbage -d

# 配置 fnm 并安装 Node.js (latest) 和 pnpm
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

# 安装 Rust 工具链
# 可通过 cargo install 安装额外软件包，这里安装 mdbook、mdbook-mermaid 作为示例
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="${HOME}/.cargo/bin:${PATH}"
RUN cargo install --locked mdbook mdbook-mermaid \
    && rm -rf ${HOME}/.cargo/registry ${HOME}/.cargo/git

# 安装 Python (Miniconda)
# 这里添加 conda-forge 源，并创建名为 common 的环境作为示例
RUN curl -LO https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    && bash Miniconda3-latest-Linux-x86_64.sh -b \
    && rm Miniconda3-latest-Linux-x86_64.sh
ENV PATH="${HOME}/miniconda3/bin:${PATH}"
RUN conda init \
    && conda config --set auto_activate false \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r \
    && conda config --remove-key channels \
    && conda config --add channels conda-forge \
    && conda create -n common python=3.13

# # 安装并配置 Claude Code
# SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# RUN curl -fsSL https://claude.ai/install.sh | bash
# SHELL ["/bin/sh", "-c"]
# RUN mkdir -p ${HOME}/.claude/
# COPY --chown=${USERNAME}:${USERNAME} claude/settings.json ${HOME}/.claude/settings.json

# 安装并配置 Codex
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

# Git 配置（请修改为你自己的信息）
RUN git config --global user.name "Your Name" \
    && git config --global user.email "your@email.com"

# ============================================================================
# SSH 配置（如不了解其作用请勿修改）
# ============================================================================

USER root

RUN mkdir -p /run/sshd/ \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

CMD ["sh", "-c", "while true; do /usr/sbin/sshd -D; sleep 1; done"]
