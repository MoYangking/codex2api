#!/usr/bin/env bash
set -euo pipefail

DATABASE_PATH="${DATABASE_PATH:-/data/codex2api.db}"
BACKUP_DIR="${BACKUP_DIR:-/home/user/backups/codex2api}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-3600}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"

log() {
  printf '[%s] [sqlite-backup] %s\n' "$(date '+%F %T')" "$*"
}

backup_once() {
  if [ ! -s "${DATABASE_PATH}" ]; then
    log "database not ready: ${DATABASE_PATH}"
    return 1
  fi

  mkdir -p "${BACKUP_DIR}"
  stamp="$(date '+%Y%m%d_%H%M%S')"
  tmp="${BACKUP_DIR}/codex2api_${stamp}.db.tmp"
  out="${BACKUP_DIR}/codex2api_${stamp}.db"
  latest_tmp="${BACKUP_DIR}/latest.db.tmp"

  sqlite3 "${DATABASE_PATH}" ".backup '${tmp}'"
  mv -f "${tmp}" "${out}"
  cp -f "${out}" "${latest_tmp}"
  mv -f "${latest_tmp}" "${BACKUP_DIR}/latest.db"
  log "backup completed: ${out}"

  if [ "${BACKUP_RETENTION_DAYS}" -gt 0 ] 2>/dev/null; then
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'codex2api_*.db' -mtime +"${BACKUP_RETENTION_DAYS}" -delete
  fi
}

/home/user/scripts/wait-for-sync.sh

if [ "${BACKUP_INTERVAL}" = "0" ]; then
  backup_once
  exit 0
fi

while true; do
  if [ ! -s "${DATABASE_PATH}" ]; then
    log "database not ready: ${DATABASE_PATH}"
    sleep 30
    continue
  fi

  backup_once || true
  sleep "${BACKUP_INTERVAL}"
done
