# codex2api Single-Port Gateway

This image wires [james-6-23/codex2api](https://github.com/james-6-23/codex2api) into the existing single-container, single-public-port layout. `supervisord` runs the internal services, while OpenResty exposes only port `7860`.

Components:
- Codex2API on `127.0.0.1:8001`
- OpenResty gateway on public port `7860`
- Optional GitHub Sync at `/sync/`
- Periodic SQLite backups under `/home/user/backups/codex2api/`
- FileBrowser at `/filebrowser/`
- GoTTY at `/t/`

The old Xvfb, NapCat, sin-proxy, MaiBot, and MaiBot Adapter build and runtime paths have been removed.
The gateway now uses native nginx `location` rules and no longer uses JSON dynamic routing.

## Routes

- `/admin/`: Codex2API dashboard
- `/health`: Codex2API health check
- `/v1/`: OpenAI-compatible API
- `/sync/`: GitHub Sync UI
- `/filebrowser/`: file manager
- `/t/`: web terminal, default `admin` / `adminadminadmin`

All unmatched requests proxy to Codex2API.

## Data And Backup

Codex2API runs in SQLite mode:

```env
DATABASE_DRIVER=sqlite
DATABASE_PATH=/data/codex2api.db
CACHE_DRIVER=memory
IMAGE_ASSET_DIR=/data/images
```

Backups run every 3600 seconds by default:

```env
BACKUP_DIR=/home/user/backups/codex2api
BACKUP_INTERVAL=3600
BACKUP_RETENTION_DAYS=14
RESTORE_SQLITE_ON_START=missing
```

On startup, the app restores from `latest.db` or the newest timestamped backup if `/data/codex2api.db` is missing.

## Optional GitHub Sync

Set these variables to persist backups and selected state into a GitHub repository:

```env
GITHUB_REPO=<owner>/<repo>
GITHUB_PAT=<token>
GIT_BRANCH=main
```

Default sync targets:
- `home/user/backups/codex2api/`
- `data/images/`
- `home/user/filebrowser-data/filebrowser.db`

If GitHub sync is not configured, Codex2API starts immediately.

## Bootstrap Access

Codex2API checks the client IP during first-time bootstrap. Because this image sits behind OpenResty, it defaults `BOOTSTRAP_ALLOWED_CIDR=0.0.0.0/0,::/0` so initialization can be completed through the public domain. After bootstrap, you can override it with a narrower IP/CIDR range.

If the hosting platform reserves the standard `Authorization` header, send `Codex-Authorization` or `X-Codex-Authorization` instead. OpenResty rewrites it back to standard `Authorization` before proxying to Codex2API, and the custom header takes precedence over a platform-provided `Authorization`.

```bash
curl https://<your-domain>/v1/models \
  -H "Codex-Authorization: Bearer <your API key>"
```

If a client cannot customize request headers and only supports an OpenAI-compatible `base_url`, put the API key in the `/ak/<key>/v1` path:

```text
base_url = https://<your-domain>/ak/<your API key>/v1
api_key = dummy
```

nginx rewrites `/ak/<key>/v1/chat/completions` to upstream `/v1/chat/completions` and injects `Authorization: Bearer <key>`. Access logs redact `/ak/<key>` as `/ak/<redacted>`.

## Local Docker

```bash
docker build -t codex2api-gateway:latest .
docker run -d \
  -p 7860:7860 \
  -e ADMIN_SECRET="<strong-secret>" \
  --name codex2api-gateway \
  codex2api-gateway:latest
```

Open `http://localhost:7860/admin/`.

Manual backup:

```bash
docker exec -e BACKUP_INTERVAL=0 codex2api-gateway /home/user/scripts/backup-sqlite.sh
```

Manual restore should be run only after stopping Codex2API, so the live SQLite file is not overwritten while it is being written:

```bash
docker exec -e RESTORE_SQLITE_ON_START=always codex2api-gateway /home/user/scripts/restore-sqlite-backup.sh
```

## Troubleshooting

For `400 Bad Request: Request Header Or Cookie Too Large`, OpenResty is configured with larger request header buffers:

```nginx
client_header_buffer_size 128k;
large_client_header_buffers 16 512k;
```

Rebuild and restart the image. If the browser still fails, clear old cookies for the domain and try again.

If `/t/` reports too many redirects, an old route may still redirect `/t` to `/t/` while GoTTY normalizes back to `/t`. The current native nginx config proxies both `/t` and `/t/` directly and no longer reads JSON route rules.

The same fix is applied to `/filebrowser/`: following the `jihuang` pattern, `/filebrowser` proxies directly to upstream `/filebrowser/` to avoid external 301 loops.

If ModelScope reserves `Authorization`, `X-modelscope-*`, or `X-studio-*`, use `Codex-Authorization: Bearer <key>` for API calls. nginx forwards only the rewritten standard `Authorization` header to Codex2API.

For clients that cannot change headers, use the path form: `https://<your-domain>/ak/<key>/v1`.
