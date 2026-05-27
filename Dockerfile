# syntax=docker/dockerfile:1.4
FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    PORT=7681 \
    PASSWORD=admin

# ── Layer 1: Core system & scanning tools ──
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates wget curl git \
        python3 python3-pip \
        tini tmux fastfetch \
        sudo net-tools iproute2 iptables procps dbus kmod dnsutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        clamav clamav-daemon yara rkhunter chkrootkit lynis \
        nuclei testssl.sh \
        nmap ncat masscan zmap \
        sqlmap nikto gobuster dirb wfuzz wpscan \
        subfinder amass assetfinder theharvester && \
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/* \
           /usr/share/info/* /var/log/* /var/lib/apt/lists/*

# ── Layer 2: Code-Server (VS Code in browser) ──
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64|amd64)  url="https://github.com/coder/code-server/releases/latest/download/code-server-linux-amd64.tar.gz" ;; \
      aarch64|arm64) url="https://github.com/coder/code-server/releases/latest/download/code-server-linux-arm64.tar.gz" ;; \
      *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    wget -qO /tmp/cs.tar.gz "$url" && \
    mkdir -p /opt/code-server && \
    tar -xzf /tmp/cs.tar.gz -C /opt/code-server --strip-components=1 && \
    rm /tmp/cs.tar.gz && \
    ln -sf /opt/code-server/bin/code-server /usr/local/bin/code-server

# ── Layer 3: User ctx + passwordless sudo ──
RUN useradd -ms /bin/bash ctx && \
    echo 'ctx:akib' | chpasswd && \
    usermod -aG sudo ctx && \
    echo 'ctx ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# ── Layer 4: Dotfiles & fastfetch ──
USER ctx
WORKDIR /home/ctx

RUN printf '%s\n' \
    'set -g mouse on' \
    'set -g status-style "bg=#1e1e2e,fg=#cdd6f4"' \
    'set -g status-left "#[bg=#89b4fa,fg=#11111b,bold] 󰆍 KALI-CODE #[bg=#1e1e2e,fg=#89b4fa] "' \
    'set -g status-right "#[fg=#a6adc8]%Y-%m-%d %H:%M "' \
    > /home/ctx/.tmux.conf

RUN printf '%s\n' \
    'if [ -x "$(command -v fastfetch)" ] && [ -z "$TMUX" ]; then fastfetch; fi' \
    'export PATH="$HOME/.local/bin:$PATH"' \
    'export PS1="\\[\\033[01;32m\\]ctx@kali-code\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "' \
    'alias ll="ls -la --color=auto"' \
    'alias grep="grep --color=auto"' \
    >> /home/ctx/.bashrc

# ── Layer 5: Code-Server config ──
RUN mkdir -p /home/ctx/.config/code-server && \
    printf '%s\n' \
    'bind-addr: 0.0.0.0:7681' \
    'auth: password' \
    'password: admin' \
    'cert: false' \
    > /home/ctx/.config/code-server/config.yaml

# ── Layer 6: Startup script (reads Railway $PORT) ──
USER root
WORKDIR /

RUN { \
    echo '#!/bin/bash'; \
    echo 'set -e'; \
    echo 'PORT="${PORT:-7681}"'; \
    echo 'PASSWORD="${PASSWORD:-admin}"'; \
    echo 'export PORT'; \
    echo 'export PASSWORD'; \
    echo 'sed -i "s/^bind-addr:.*/bind-addr: 0.0.0.0:${PORT}/" /home/ctx/.config/code-server/config.yaml'; \
    echo 'sed -i "s/^password:.*/password: ${PASSWORD}/" /home/ctx/.config/code-server/config.yaml'; \
    echo 'chown -R ctx:ctx /home/ctx/.config'; \
    echo 'echo "Starting Code-Server on port ${PORT}..."'; \
    echo 'exec su - ctx -c "code-server --config /home/ctx/.config/code-server/config.yaml /home/ctx"'; \
    } > /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

EXPOSE 7681

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start.sh"]
