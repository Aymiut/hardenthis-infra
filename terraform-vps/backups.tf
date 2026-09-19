# ---------------------------------------------------------------------------
# Database backups bucket — PRIVATE.
#
# Holds the nightly pg_dump of the VPS Postgres (user PII + bcrypt hashes).
# Unlike the assets bucket, this one is fully locked down: all public access
# blocked, SSE-S3 at rest, versioning on, 30-day lifecycle expiry. Written to
# by a dedicated least-privilege IAM user (vps-backup) running the backup job
# on the VPS.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "backups" {
  bucket = "${local.name_prefix}-backups"

  tags = { Name = "${local.name_prefix}-backups" }
}

# Block ALL public access — backups must never be reachable publicly.
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning protects against an overwrite/corruption of a dump.
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Retention: current dumps expire after 30 days, noncurrent versions 7 days
# later. Aborts stuck multipart uploads so they don't accumulate cost.
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------------------
# Least-privilege IAM user for the VPS backup job.
# Can write dumps and read them back (for restore). No delete — the lifecycle
# rule handles expiry, so a compromised key cannot wipe the backup history.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "vps_backup" {
  name = "${local.name_prefix}-vps-backup"
}

data "aws_iam_policy_document" "vps_backup" {
  statement {
    sid       = "WriteAndReadBackups"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.backups.arn}/*"]
  }

  statement {
    sid       = "ListBackupsBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
  }
}

resource "aws_iam_user_policy" "vps_backup" {
  name   = "${local.name_prefix}-vps-backup-permissions"
  user   = aws_iam_user.vps_backup.name
  policy = data.aws_iam_policy_document.vps_backup.json
}

resource "aws_iam_access_key" "vps_backup" {
  user = aws_iam_user.vps_backup.name
}

# ---------------------------------------------------------------------------
# Outputs (kept here to keep this change self-contained).
# Retrieve the secret with: terraform output -raw vps_backup_secret_access_key
# ---------------------------------------------------------------------------

output "backups_bucket" {
  value = aws_s3_bucket.backups.id
}

output "vps_backup_access_key_id" {
  value = aws_iam_access_key.vps_backup.id
}

output "vps_backup_secret_access_key" {
  value     = aws_iam_access_key.vps_backup.secret
  sensitive = true
}
