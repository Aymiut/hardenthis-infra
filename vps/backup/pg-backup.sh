#!/usr/bin/env bash
#
# Nightly Postgres backup for hardenthis → private S3 bucket.
#
# Runs on the VPS host as the `hardenthis` user (member of the docker group;
# NO root needed). Dumps the Postgres container with pg_dump (custom format),
# verifies the archive is readable, then uploads it to the private, encrypted,
# versioned S3 backup bucket. Retention is handled by the bucket lifecycle rule.
#
# The DB password never touches the host: pg_dump runs *inside* the container
# and reads POSTGRES_PASSWORD from the container's own environment.
#
set -euo pipefail

PG_CONTAINER="hardenthis-postgres-1"
S3_BUCKET="hardenthis-prod-backups"
AWS_REGION="eu-west-3"
AWSCLI_IMAGE="amazon/aws-cli:latest"
CREDS_FILE="/opt/hardenthis/backup/backup-creds.env"

TMP_DIR="$(mktemp -d /tmp/hardenthis-backup.XXXXXX)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# --- dead-man's-switch ping (healthchecks.io) ---
# Optional: if HEALTHCHECK_URL is unset the pings are silently skipped, so a
# missing alerting config can NEVER break the backup itself. healthchecks.io
# alerts us when it stops hearing the success ping — which also catches the
# worst case "the job never ran at all" (VPS down, timer disabled, docker dead).
hc_ping() {
  local suffix="${1:-}" body="${2:-}"
  [ -n "${HEALTHCHECK_URL:-}" ] || return 0
  curl -fsS -m 10 --retry 3 --data-raw "$body" "${HEALTHCHECK_URL}${suffix}" \
    >/dev/null 2>&1 || true
}

fail() { log "ERROR: $*"; hc_ping "/fail" "$*"; exit 1; }

# --- AWS credentials (vps-backup IAM user: least-priv on the backup bucket) ---
[ -r "$CREDS_FILE" ] || fail "credentials file not readable: $CREDS_FILE"
# shellcheck disable=SC1090
set -a; source "$CREDS_FILE"; set +a
: "${AWS_ACCESS_KEY_ID:?missing in creds file}"
: "${AWS_SECRET_ACCESS_KEY:?missing in creds file}"

# Signal "job started" now that HEALTHCHECK_URL (if any) is loaded. Gives us the
# run duration on the dashboard and lets healthchecks.io flag a job that hangs.
hc_ping "/start"

# --- sanity: the postgres container must be running ---
docker inspect -f '{{.State.Running}}' "$PG_CONTAINER" 2>/dev/null | grep -q true \
  || fail "container $PG_CONTAINER is not running"

# --- resolve DB name from the container's own env (no secret on the host) ---
DB_NAME="$(docker exec "$PG_CONTAINER" printenv POSTGRES_DB)"
[ -n "$DB_NAME" ] || fail "could not resolve POSTGRES_DB"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DUMP_FILE="$TMP_DIR/hardenthis-${STAMP}.dump"
S3_KEY="postgres/${DB_NAME}/$(date -u +%Y/%m/%d)/hardenthis-${STAMP}.dump"

# --- dump (custom format: compressed + selectively restorable) ---
log "Dumping '${DB_NAME}' from ${PG_CONTAINER}"
docker exec "$PG_CONTAINER" sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$DUMP_FILE"

SIZE="$(stat -c%s "$DUMP_FILE")"
[ "$SIZE" -ge 1000 ] || fail "dump suspiciously small (${SIZE} bytes) — not uploading"
log "Dump written: ${SIZE} bytes"

# --- integrity check: the archive table-of-contents must be readable ---
docker exec -i "$PG_CONTAINER" pg_restore --list < "$DUMP_FILE" > /dev/null 2>&1 \
  || fail "pg_restore --list failed — dump is corrupt, not uploading"
log "Integrity check OK"

# --- upload to S3 via the official aws-cli image (no host aws-cli needed) ---
log "Uploading to s3://${S3_BUCKET}/${S3_KEY}"
docker run --rm \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION="$AWS_REGION" \
  -v "$TMP_DIR:/data:ro" \
  "$AWSCLI_IMAGE" \
  s3 cp "/data/$(basename "$DUMP_FILE")" "s3://${S3_BUCKET}/${S3_KEY}" --only-show-errors \
  || fail "S3 upload failed"

log "Backup OK: s3://${S3_BUCKET}/${S3_KEY} (${SIZE} bytes)"

# Signal success — resets the dead-man's-switch timer. Silence past the grace
# window (no ping here) is what triggers the alert.
hc_ping
