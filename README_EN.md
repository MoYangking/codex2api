# codex2api Single-Port Gateway

This image wires [james-6-23/codex2api](https://github.com/james-6-23/codex2api) into the existing single-container, single-public-port layout. `supervisord` runs the internal services, while OpenResty exposes only port `7860`.

Components:
- Codex2API on `127.0.0.1:8001`
- OpenResty gateway on public port `7860`
- Optional GitHub Sync at `/sync/`
- Periodic SQLite backups under `/home/user/backups/codex2api/`
- FileBrowser at `/filebrowser/`
- GoTTY at `/t/`
- Route admin UI at `/admin/ui/`

The old Xvfb, NapCat, sin-proxy, MaiBot, and MaiBot Adapter build and runtime paths have been removed.

## Routes

- `/admin/`: Codex2API dashboard
- `/health`: Codex2API health check
- `/v1/`: OpenAI-compatible API
- `/admin/ui/`: OpenResty route admin, default password `admin`
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
- `home/user/nginx/admin_config.json`
- `home/user/filebrowser-data/filebrowser.db`

If GitHub sync is not configured, Codex2API starts immediately.

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
client_header_buffer_size 32k;
large_client_header_buffers 8 128k;
```

Rebuild and restart the image. If the browser still fails, clear old cookies for the domain and try again.
