#!/usr/bin/env bash
set -euo pipefail

export CODEX_BIND="${CODEX_BIND:-127.0.0.1}"
export CODEX_PORT="${CODEX_PORT:-8080}"
export DATABASE_DRIVER="${DATABASE_DRIVER:-sqlite}"
export DATABASE_PATH="${DATABASE_PATH:-/data/codex2api.db}"
export CACHE_DRIVER="${CACHE_DRIVER:-memory}"
export IMAGE_ASSET_DIR="${IMAGE_ASSET_DIR:-/data/images}"
export LOG_DIR="${LOG_DIR:-/home/user/logs/codex2api}"
export BACKUP_DIR="${BACKUP_DIR:-/home/user/backups/codex2api}"

mkdir -p "$(dirname "${DATABASE_PATH}")" "${IMAGE_ASSET_DIR}" "${LOG_DIR}" "${BACKUP_DIR}"

/home/user/scripts/wait-for-sync.sh
/home/user/scripts/restore-sqlite-backup.sh

exec /home/user/codex2api
