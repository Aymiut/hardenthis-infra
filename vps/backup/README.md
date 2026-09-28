# Postgres backups — hardenthis

Daily backup of the VPS Postgres database to a **private, encrypted and
versioned** S3 bucket (`hardenthis-prod-backups`, region `eu-west-3`).

## Architecture

```
VPS (hardenthis user, docker group)
  └─ systemd timer (03:30 UTC) ─▶ pg-backup.sh
       ├─ docker exec hardenthis-postgres-1  pg_dump -Fc   (read-only)
       ├─ verifies the archive (pg_restore --list)
       └─ docker run amazon/aws-cli  s3 cp ──▶ s3://hardenthis-prod-backups/
                                                  postgres/<db>/YYYY/MM/DD/hardenthis-<UTC>.dump
```

- **Format**: `pg_dump -Fc` (custom, compressed, selectively restorable).
- **The DB password never leaves the container**: `pg_dump` reads
  `POSTGRES_PASSWORD` from the Postgres container's environment.
- **AWS credentials**: dedicated IAM user `hardenthis-prod-vps-backup` (least-priv:
  `PutObject`/`GetObject`/`ListBucket` on this bucket **only**, no
  `Delete`). Stored in `/opt/hardenthis/backup/backup-creds.env` (chmod 600).
- **Retention**: S3 lifecycle — current objects expire after 30 days, noncurrent
  versions 7 days later. (Not handled by the script.)
- **AWS infra**: defined in `infra/terraform-vps/backups.tf`.

## Files (on the VPS: `/opt/hardenthis/backup/`)

| File | Purpose |
|---|---|
| `pg-backup.sh` | The backup job (dump → check → S3 upload). |
| `restore-test.sh` | Checks that an S3 dump can be restored (throwaway scratch database). |
| `backup-creds.env` | AWS keys for the `vps-backup` IAM user (chmod 600, **not versioned**). |
| `hardenthis-backup.service` / `.timer` | systemd units (scheduling). |

## Installing the timer (one-shot, requires root)

```bash
sudo install -m 644 /opt/hardenthis/backup/hardenthis-backup.service /etc/systemd/system/
sudo install -m 644 /opt/hardenthis/backup/hardenthis-backup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hardenthis-backup.timer
sudo systemctl list-timers hardenthis-backup.timer   # check the next trigger
```

## Running a backup manually

```bash
/opt/hardenthis/backup/pg-backup.sh
```

## Checking that a backup can be restored (without touching prod)

```bash
# list the backups
aws s3 ls --recursive s3://hardenthis-prod-backups/postgres/   # or via the console

# restore into a throwaway scratch database and compare with prod
/opt/hardenthis/backup/restore-test.sh postgres/hardenthis/YYYY/MM/DD/hardenthis-<UTC>.dump
```

The script creates `hardenthis_restore_test`, restores the dump into it, compares
the row count of **every table** with the live database, then drops the scratch
database. Only volatile tables (`refreshtokens`, `verification_tokens`) may
legitimately differ if the dump is older.

## REAL RESTORE (disaster recovery — know what you are doing)

> ⚠️ Overwrites data. Only do this on an explicit decision.

```bash
KEY="postgres/hardenthis/YYYY/MM/DD/hardenthis-<UTC>.dump"
TMP=$(mktemp -d)
set -a; source /opt/hardenthis/backup/backup-creds.env; set +a

# 1. fetch the dump
docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  -e AWS_DEFAULT_REGION=eu-west-3 -v "$TMP:/data" amazon/aws-cli \
  s3 cp "s3://hardenthis-prod-backups/$KEY" /data/restore.dump
docker cp "$TMP/restore.dump" hardenthis-postgres-1:/tmp/restore.dump

# 2. (recommended) stop the backend to avoid concurrent writes
cd /opt/hardenthis && docker compose stop backend

# 3. restore into the prod database (--clean --if-exists replaces the objects)
docker exec hardenthis-postgres-1 sh -c \
  'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
     --clean --if-exists --no-owner /tmp/restore.dump'

# 4. restart the backend
docker compose start backend
docker exec hardenthis-postgres-1 rm -f /tmp/restore.dump; rm -rf "$TMP"
```

## Monitoring — dead-man's switch (healthchecks.io)

The job always logs to the systemd journal:
```bash
journalctl -u hardenthis-backup.service -n 50
```

On top of that, `pg-backup.sh` pings a **dead-man's switch**: healthchecks.io
alerts if the success ping doesn't arrive within the expected window. The
advantage over a plain `OnFailure=`: it also catches the case where **the job
never ran** (VPS down, timer disabled, docker dead), not just a failed run.

The script sends three signals (via `HEALTHCHECK_URL`):
- `…/start` — on startup (gives the run duration and catches a job that hangs);
- `…` (success) — at the end of the job, re-arms the timer;
- `…/fail` — on error, with the failure message as the request body.

**The ping is optional**: if `HEALTHCHECK_URL` is not set, the pings are
silently skipped — a missing alerting config can **never** break the backup
itself.

### Setup (once)

1. On [healthchecks.io](https://healthchecks.io) (the free tier is enough), create a
   check: **Period = 1 day**, **Grace = 1 hour**, name `hardenthis-pg-backup`.
   Hook up a notification integration (email / Slack / Discord).
2. Copy the check's ping URL (`https://hc-ping.com/<uuid>`).
3. Add it to `/opt/hardenthis/backup/backup-creds.env` (chmod 600, not versioned):
   ```bash
   HEALTHCHECK_URL=https://hc-ping.com/<uuid>
   ```
4. Test: `/opt/hardenthis/backup/pg-backup.sh` → the check should go **up**
   on the dashboard (and a failed run should turn it **down** and notify).

> ⚠️ Deploying the script to the VPS is **manual** (the `infra` repo has no
> CI). Copy the updated `pg-backup.sh` into `/opt/hardenthis/backup/`; no
> `daemon-reload` is needed (only the `.service`/`.timer` files require one).
