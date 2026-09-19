variable "aws_region" {
  description = "AWS region for lab infrastructure (recommended: eu-west-3 Paris for FR latency)"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  type    = string
  default = "hardenthis"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "vps_public_ip" {
  description = "Public IPv4 of the VPS — used to whitelist ingress on lab security group"
  type        = string
  # Example: "203.0.113.42". MUST be the real VPS IP before apply.
}

variable "s3_assets_bucket" {
  description = "S3 bucket name for user uploads (created by this stack — must be globally unique)"
  type        = string
  default     = "hardenthis-prod-assets"
}

variable "domain_name" {
  description = "Site root domain — used to scope S3 CORS"
  type        = string
  default     = "hardenthis.com"
}
