# infra/terraform/variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID (12 digits)"
  type        = string
}

variable "environment" {
  description = "Environment name (prod / staging)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name used as resource prefix"
  type        = string
  default     = "defendarcade"
}

# ---------------------------------------------------------------------------
# DNS / TLS
# ---------------------------------------------------------------------------

variable "domain_name" {
  description = "Primary public domain (e.g. hardenthis.com)"
  type        = string
  default     = "hardenthis.com"
}

# ---------------------------------------------------------------------------
# ECR images (already pushed by GitLab CI)
# Format: <account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>
# ---------------------------------------------------------------------------

variable "ecr_backend_image" {
  description = "ECR image URI for the NestJS backend"
  type        = string
}

variable "ecr_frontend_image" {
  description = "ECR image URI for the Next.js frontend"
  type        = string
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "defendarcade"
}

variable "db_password" {
  description = "RDS master password (stored in Secrets Manager)"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "defendarcade"
}

# ---------------------------------------------------------------------------
# Secrets (stored in Secrets Manager, injected into ECS)
# ---------------------------------------------------------------------------

variable "jwt_access_secret" {
  description = "JWT access token signing secret"
  type        = string
  sensitive   = true
}

variable "jwt_refresh_secret" {
  description = "JWT refresh token signing secret"
  type        = string
  sensitive   = true
}

variable "admin_sync_secret" {
  description = "X-Admin-Secret for CI/CD lab sync endpoint"
  type        = string
  sensitive   = true
}

variable "terminal_secret" {
  description = "Secret for terminal authentication"
  type        = string
  sensitive   = true
}

variable "redis_auth_token" {
  description = "Auth token for Redis (ElastiCache) access"
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Traefik EC2
# ---------------------------------------------------------------------------

variable "traefik_instance_type" {
  description = "EC2 instance type for Traefik"
  type        = string
  default     = "t3.small"
}
