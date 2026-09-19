# =============================================================================
# modules/s3-assets/main.tf — S3 bucket for platform images (labs, courses, users)
# Served via Cloudflare CDN (cdn.<domain>)
# =============================================================================

resource "aws_s3_bucket" "assets" {
  bucket        = "cdn.${var.domain_name}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "assets_public_read" {
  bucket = aws_s3_bucket.assets.id

  depends_on = [aws_s3_bucket_public_access_block.assets]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.assets.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_cors_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT"]
    allowed_origins = [
      "https://${var.domain_name}",
      "https://www.${var.domain_name}",
      "http://localhost:3001",
    ]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
