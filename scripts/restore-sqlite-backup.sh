#!/usr/bin/env bash
set -euo pipefail

DATABASE_PATH="${DATABASE_PATH:-/data/codex2api.db}"
BACKUP_DIR="${BACKUP_DIR:-/home/user/backups/codex2api}"
RESTORE_SQLITE_ON_START="${RESTORE_SQLITE_ON_START:-missing}"

log() {
  printf '[%s] [sqlite-restore] %s\n' "$(date '+%F %T')" "$*"
}

if [ "${RESTORE_SQLITE_ON_START}" = "never" ]; then
  log "restore disabled"
  exit 0
fi

if [ -s "${DATABASE_PATH}" ] && [ "${RESTORE_SQLITE_ON_START}" != "always" ]; then
  log "database already exists, skipping restore"
  exit 0
fi

if [ -s "${BACKUP_DIR}/latest.db" ]; then
  src="${BACKUP_DIR}/latest.db"
else
  src="$(find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'codex2api_*.db' 2>/dev/null | sort | tail -n 1 || true)"
fi

if [ -z "${src:-}" ] || [ ! -s "${src}" ]; then
  log "no backup found"
  exit 0
fi

mkdir -p "$(dirname "${DATABASE_PATH}")"
tmp="${DATABASE_PATH}.restore.tmp"
cp -f "${src}" "${tmp}"
mv -f "${tmp}" "${DATABASE_PATH}"
log "restored ${DATABASE_PATH} from ${src}"
