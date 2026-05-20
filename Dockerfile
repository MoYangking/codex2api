FROM ubuntu:24.04

# Default mirrors. Override these when building in a slower network.
ARG APT_MIRROR=http://azure.archive.ubuntu.com/ubuntu
ARG PIP_INDEX_URL=https://pypi.org/simple/

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

RUN set -eux; \
    mirror="${APT_MIRROR%/}"; \
    if [ -f /etc/apt/sources.list ]; then \
      sed -i "s|http://archive.ubuntu.com/ubuntu|${mirror}|g; s|http://security.ubuntu.com/ubuntu|${mirror}|g" /etc/apt/sources.list; \
    fi; \
    if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
      sed -i "s|http://archive.ubuntu.com/ubuntu|${mirror}|g; s|http://security.ubuntu.com/ubuntu|${mirror}|g" /etc/apt/sources.list.d/ubuntu.sources; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release bash tar gzip \
    git jq rsync sqlite3 \
    python3 python3-pip python3-venv \
    supervisor nginx-full \
 && rm -rf /var/lib/apt/lists/*

# Install OpenResty (nginx with built-in LuaJIT and ngx_lua).
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release; \
    curl -fsSL https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" \
      | tee /etc/apt/sources.list.d/openresty.list > /dev/null; \
    apt-get update && apt-get install -y --no-install-recommends openresty; \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/user /data && chown -R 1000:1000 /home/user /data
ENV HOME=/home/user \
    VIRTUAL_ENV=/home/user/.venv \
    PATH=/home/user/.venv/bin:/home/user/.local/bin:/usr/local/openresty/bin:$PATH
WORKDIR /home/user

RUN python3 -m venv "$VIRTUAL_ENV" && \
    "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --upgrade pip && \
    "$VIRTUAL_ENV/bin/pip" install --no-cache-dir --index-url "${PIP_INDEX_URL}" fastapi uvicorn httpx

# Download the latest codex2api release binary and verify it with SHA256SUMS.txt.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) codex_arch="amd64" ;; \
      arm64) codex_arch="arm64" ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    release_json="$(curl -fsSL https://api.github.com/repos/james-6-23/codex2api/releases/latest)"; \
    asset_name="$(printf '%s' "${release_json}" | jq -r --arg suffix "linux_${codex_arch}.tar.gz" '.assets[] | select(.name | endswith($suffix)) | .name' | head -n 1)"; \
    asset_url="$(printf '%s' "${release_json}" | jq -r --arg name "${asset_name}" '.assets[] | select(.name == $name) | .browser_download_url' | head -n 1)"; \
    sums_url="$(printf '%s' "${release_json}" | jq -r '.assets[] | select(.name == "SHA256SUMS.txt") | .browser_download_url' | head -n 1)"; \
    test -n "${asset_name}"; \
    test -n "${asset_url}"; \
    test -n "${sums_url}"; \
    curl -fL --retry 3 --retry-delay 1 -o /tmp/codex2api.tar.gz "${asset_url}"; \
    curl -fL --retry 3 --retry-delay 1 -o /tmp/SHA256SUMS.txt "${sums_url}"; \
    grep "  ${asset_name}$" /tmp/SHA256SUMS.txt | sed "s#  ${asset_name}#  /tmp/codex2api.tar.gz#" | sha256sum -c -; \
    mkdir -p /tmp/codex2api-release; \
    tar -xzf /tmp/codex2api.tar.gz -C /tmp/codex2api-release; \
    install -m 0755 /tmp/codex2api-release/codex2api /home/user/codex2api; \
    chown 1000:1000 /home/user/codex2api; \
    rm -rf /tmp/codex2api-release /tmp/codex2api.tar.gz /tmp/SHA256SUMS.txt

# Download and install FileBrowser.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) fb_arch="amd64" ;; \
      arm64) fb_arch="arm64" ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    LATEST_URL="$(curl -fsSL https://api.github.com/repos/filebrowser/filebrowser/releases/latest | \
      jq -r --arg suffix "linux-${fb_arch}-filebrowser.tar.gz" '.assets[] | select(.name | endswith($suffix)) | .browser_download_url' | \
      head -n 1 | tr -d '\r')"; \
    test -n "${LATEST_URL}"; \
    curl -fL -o /tmp/filebrowser.tar.gz "${LATEST_URL}"; \
    tar -xzf /tmp/filebrowser.tar.gz -C /tmp; \
    mv /tmp/filebrowser /home/user/filebrowser; \
    chmod +x /home/user/filebrowser; \
    chown 1000:1000 /home/user/filebrowser; \
    rm -f /tmp/filebrowser.tar.gz; \
    mkdir -p /home/user/filebrowser-data; \
    chown -R 1000:1000 /home/user/filebrowser-data

# Download and install GoTTY (web terminal).
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
      amd64) gotty_arch="amd64" ;; \
      arm64) gotty_arch="arm64" ;; \
      *) echo "Unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    LATEST_URL="$(curl -fsSL https://api.github.com/repos/sorenisanerd/gotty/releases/latest | \
      jq -r --arg arch "${gotty_arch}" '.assets[] | select(.name | test("gotty_v.*_linux_" + $arch + "\\.tar\\.gz$")) | .browser_download_url' | \
      head -n 1 | tr -d '\r')"; \
    test -n "${LATEST_URL}"; \
    curl -fL -o /tmp/gotty.tar.gz "${LATEST_URL}"; \
    tar -xzf /tmp/gotty.tar.gz -C /tmp; \
    mv /tmp/gotty /home/user/gotty; \
    chmod +x /home/user/gotty; \
    chown 1000:1000 /home/user/gotty; \
    rm -f /tmp/gotty.tar.gz

# Install Cloudflare Tunnel client from the official Cloudflare apt repository.
RUN set -eux; \
    mkdir -p --mode=0755 /usr/share/keyrings; \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
      | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null; \
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
      > /etc/apt/sources.list.d/cloudflared.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends cloudflared; \
    rm -rf /var/lib/apt/lists/*; \
    cloudflared --version

RUN mkdir -p /home/user/logs /home/user/backups/codex2api /data/images && \
    chown -R 1000:1000 /home/user/logs /home/user/backups /data

COPY --chown=1000:1000 supervisor/supervisord.conf /home/user/supervisord.conf
RUN mkdir -p /home/user/nginx && chown -R 1000:1000 /home/user/nginx
COPY --chown=1000:1000 nginx/nginx.conf /home/user/nginx/nginx.conf
RUN mkdir -p \
      /home/user/nginx/tmp/body \
      /home/user/nginx/tmp/proxy \
      /home/user/nginx/tmp/fastcgi \
      /home/user/nginx/tmp/uwsgi \
      /home/user/nginx/tmp/scgi \
    && chown -R 1000:1000 /home/user/nginx

COPY --chown=1000:1000 sync /home/user/sync

RUN mkdir -p /home/user/scripts && chown -R 1000:1000 /home/user/scripts
COPY --chown=1000:1000 scripts/run-codex2api.sh /home/user/scripts/run-codex2api.sh
COPY --chown=1000:1000 scripts/run-cloudflared.sh /home/user/scripts/run-cloudflared.sh
COPY --chown=1000:1000 scripts/backup-sqlite.sh /home/user/scripts/backup-sqlite.sh
COPY --chown=1000:1000 scripts/restore-sqlite-backup.sh /home/user/scripts/restore-sqlite-backup.sh
COPY --chown=1000:1000 scripts/wait-sync-ready.sh /home/user/scripts/wait-sync-ready.sh
COPY --chown=1000:1000 scripts/wait-for-sync.sh /home/user/scripts/wait-for-sync.sh
RUN sed -i 's/\r$//' /home/user/scripts/*.sh && chmod +x /home/user/scripts/*.sh

ENV CODEX_BIND=127.0.0.1 \
    CODEX_PORT=8001 \
    DATABASE_DRIVER=sqlite \
    DATABASE_PATH=/data/codex2api.db \
    CACHE_DRIVER=memory \
    IMAGE_ASSET_DIR=/data/images \
    BOOTSTRAP_ALLOWED_CIDR=0.0.0.0/0,::/0 \
    LOG_DIR=/home/user/logs/codex2api \
    BACKUP_DIR=/home/user/backups/codex2api \
    BACKUP_INTERVAL=3600 \
    BACKUP_RETENTION_DAYS=14

EXPOSE 7860

CMD ["supervisord", "-c", "/home/user/supervisord.conf"]
