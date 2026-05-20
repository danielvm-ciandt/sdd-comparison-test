#!/bin/bash
# backup.sh — Refactored (SABR Task C)
set -euo pipefail

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_DIR:-/tmp/backups}"

# ── Error handling ──────────────────────────────────────────────────────────
cleanup() {
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "ERROR: script failed (exit $exit_code)" >&2
  fi
  rm -f "$BACKUP_DIR"/*.dump "$BACKUP_DIR"/*.dump.gz 2>/dev/null || true
}
trap cleanup EXIT

# ── Helper functions ────────────────────────────────────────────────────────
notify_slack() {
  local webhook="${SLACK_WEBHOOK:-}"
  local message="$1"
  if [ -n "$webhook" ]; then
    curl -s -X POST "$webhook" \
      -H 'Content-type: application/json' \
      -d "{\"text\": \"$message\"}" || true
  fi
}

upload_to_s3() {
  local file="$1"
  local dest="$2"
  aws s3 cp "$file" "$dest" --region "${AWS_REGION:-us-east-1}"
}

backup_db() {
  local env="$1"
  local host="$2"
  local dbname="$3"
  local dump_file="$BACKUP_DIR/${env}_${DATE}.dump"
  mkdir -p "$BACKUP_DIR"
  PGPASSWORD="${PGPASSWORD:-}" pg_dump -h "$host" -U "${PGUSER:-admin}" \
    -d "$dbname" -F c -f "$dump_file"
  echo "$dump_file"
}

compress_file() {
  local file="$1"
  gzip "$file"
  echo "${file}.gz"
}

backup_and_upload() {
  local env="$1"
  local host="$2"
  local dbname="$3"
  local s3_bucket="${4:-${S3_BUCKET:-s3://mycompany-backups}}"
  echo "Starting backup for $env database..."
  local dump
  dump=$(backup_db "$env" "$host" "$dbname")
  local gz
  gz=$(compress_file "$dump")
  echo "Uploading $env backup to S3..."
  upload_to_s3 "$gz" "${s3_bucket}/${env}/${DATE}/"
  rm -f "$gz"
  notify_slack "✅ ${env} DB backup completed: $(basename "$gz")"
  echo "Backup complete for $env"
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  backup_and_upload "production" "${DB_PROD_HOST:-db-prod.internal}" "production"
  backup_and_upload "staging"    "${DB_STAGE_HOST:-db-staging.internal}" "staging"
  backup_and_upload "analytics"  "${DB_ANALYTICS_HOST:-db-analytics.internal}" "analytics"
}

main "$@"
