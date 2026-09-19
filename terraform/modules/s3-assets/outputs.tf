output "bucket_name" {
  description = "S3 bucket name for assets"
  value       = aws_s3_bucket.assets.bucket
}

output "bucket_arn" {
  description = "S3 bucket ARN for IAM policies"
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain" {
  description = "S3 bucket regional domain name (for Cloudflare CNAME)"
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
