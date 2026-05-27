# syntax=docker/dockerfile:1.4
FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    PORT=7681 \
    USERNAME=admin \
    PASSWORD=admin

# ── Layer 1: Core system & utilities ──
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates wget curl git \
        python3 python3-pip \
        tini tmux fastfetch \
        sudo net-tools iproute2 iptables procps dbus kmod dnsutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# ── Layer 2: The scanning / recon / threat-detection arsenal ──
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fastfetch \
        clamav clamav-daemon yara rkhunter chkrootkit lynis \
        nuclei testssl.sh \
        nmap ncat masscan zmap \
        sqlmap nikto gobuster dirb wfuzz wpscan \
        subfinder amass assetfinder theharvester && \
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/* \
           /usr/share/info/* /var/log/* /var/lib/apt/lists/* /var/cache/apt/*

# ── Layer 3: ttyd (web terminal) ──
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64|amd64) ttyd_asset="ttyd.x86_64" ;; \
      aarch64|arm64) ttyd_asset="ttyd.aarch64" ;; \
      *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    wget -qO /usr/local/bin/ttyd \
        "https://github.com/tsl0922/ttyd/releases/latest/download/${ttyd_asset}" && \
    chmod +x /usr/local/bin/ttyd

# ── Layer 4: User ctx + passwordless sudo ──
RUN useradd -ms /bin/bash ctx && \
    echo 'ctx:akib' | chpasswd && \
    usermod -aG sudo ctx && \
    echo 'ctx ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# ── Layer 5: Dotfiles & fastfetch ──
USER ctx
WORKDIR /home/ctx

RUN printf '%s\n' \
    'set -g mouse on' \
    'set -g status-style "bg=#1e1e2e,fg=#cdd6f4"' \
    'set -g status-left "#[bg=#89b4fa,fg=#11111b,bold] 󰆍 KALI-SCAN #[bg=#1e1e2e,fg=#89b4fa] "' \
    'set -g status-right "#[fg=#a6adc8]%Y-%m-%d %H:%M "' \
    > /home/ctx/.tmux.conf

RUN printf '%s\n' \
    'if [ -x "$(command -v fastfetch)" ] && [ -z "$TMUX" ]; then fastfetch; fi' \
    'export PATH="$HOME/.local/bin:$PATH"' \
    'export PS1="\\[\\033[01;32m\\]ctx@kali-scan\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "' \
    'alias ll="ls -la --color=auto"' \
    'alias grep="grep --color=auto"' \
    >> /home/ctx/.bashrc

# ── Layer 6: Root fallback & startup script ──
USER root
WORKDIR /
RUN echo "fastfetch || true" >> /root/.bashrc

RUN { \
    echo '#!/bin/bash'; \
    echo 'set -e'; \
    echo 'PORT="${PORT:-7681}"'; \
    echo 'USERNAME="${USERNAME:-admin}"'; \
    echo 'PASSWORD="${PASSWORD:-admin}"'; \
    echo 'echo "Starting ttyd on port ${PORT}..."'; \
    echo 'exec /usr/local/bin/ttyd \\'; \
    echo '    --writable \\'; \
    echo '    -i 0.0.0.0 \\'; \
    echo '    -p "${PORT}" \\'; \
    echo '    -c "${USERNAME}:${PASSWORD}" \\'; \
    echo '    /bin/su - ctx'; \
    } > /usr/local/bin/start.sh && chmod +x /usr/local/bin/start.sh

EXPOSE 7681 22 80 443 3000 4444 8080 8444 9090 4000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/start.sh"]
