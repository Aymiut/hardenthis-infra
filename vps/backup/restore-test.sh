#!/usr/bin/env bash
#
# Restore-verification for hardenthis Postgres backups.
#
# Downloads a dump from the S3 backup bucket and restores it into a THROWAWAY
# scratch database in the Postgres container, then compares the per-table row
# counts against the live database. The production database is NEVER touched.
# The scratch DB is dropped on exit (success or failure).
#
# Usage: restore-test.sh <s3-key>
#   e.g. restore-test.sh postgres/hardenthis/2026/06/15/hardenthis-20260615T194610Z.dump
#
set -euo pipefail

PG_CONTAINER="hardenthis-postgres-1"
S3_BUCKET="hardenthis-prod-backups"
AWS_REGION="eu-west-3"
AWSCLI_IMAGE="amazon/aws-cli:latest"
CREDS_FILE="/opt/hardenthis/backup/backup-creds.env"
SCRATCH_DB="hardenthis_restore_test"

S3_KEY="${1:-}"
[ -n "$S3_KEY" ] || { echo "usage: $0 <s3-key>"; exit 1; }

set -a; source "$CREDS_FILE"; set +a

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
  docker exec "$PG_CONTAINER" rm -f /tmp/restore-test.dump 2>/dev/null || true
  docker exec "$PG_CONTAINER" sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" dropdb -U "$POSTGRES_USER" --if-exists '"$SCRATCH_DB" 2>/dev/null || true
}
trap cleanup EXIT

echo "[*] Downloading s3://$S3_BUCKET/$S3_KEY"
docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION="$AWS_REGION" \
  -v "$TMP:/data" "$AWSCLI_IMAGE" \
  s3 cp "s3://$S3_BUCKET/$S3_KEY" /data/restore-test.dump --only-show-errors

docker cp "$TMP/restore-test.dump" "$PG_CONTAINER:/tmp/restore-test.dump"

echo "[*] Creating fresh scratch DB ($SCRATCH_DB)"
docker exec "$PG_CONTAINER" sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" dropdb -U "$POSTGRES_USER" --if-exists '"$SCRATCH_DB"
docker exec "$PG_CONTAINER" sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" createdb -U "$POSTGRES_USER" '"$SCRATCH_DB"

echo "[*] Restoring into $SCRATCH_DB"
docker exec "$PG_CONTAINER" sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U "$POSTGRES_USER" -d '"$SCRATCH_DB"' /tmp/restore-test.dump'

# Per-table row-count snapshot. SQL is fed via stdin to avoid shell-quoting hell.
read -r -d '' SNAP_SQL <<'SQL' || true
SELECT table_name,
  (xpath('/row/cnt/text()',
     query_to_xml(format('SELECT count(*) AS cnt FROM %I.%I', table_schema, table_name),
                  false, true, '')))[1]::text::bigint AS rows
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
ORDER BY table_name;
SQL

snapshot() { # $1 = target db
  echo "$SNAP_SQL" | docker exec -i -e TARGET_DB="$1" "$PG_CONTAINER" \
    sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" psql -U "$POSTGRES_USER" -d "$TARGET_DB" -tA -f -'
}

PROD_DB="$(docker exec "$PG_CONTAINER" printenv POSTGRES_DB)"
echo "[*] Comparing per-table row counts: $PROD_DB (live) vs $SCRATCH_DB (restored)"
snapshot "$PROD_DB"    > "$TMP/prod.txt"
snapshot "$SCRATCH_DB" > "$TMP/restore.txt"

echo "    live tables: $(wc -l < "$TMP/prod.txt"), restored tables: $(wc -l < "$TMP/restore.txt")"
if diff -u "$TMP/prod.txt" "$TMP/restore.txt"; then
  echo "[OK] RESTORE TEST PASSED — every table matches the live DB row-for-row"
else
  echo "[!!] Differences above. Note: volatile tables (sessions/tokens) may legitimately"
  echo "     differ if the dump was taken earlier. Review before concluding failure."
  exit 1
fi
