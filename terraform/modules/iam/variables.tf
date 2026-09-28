# =============================================================================
# variables.tf - IAM module inputs
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Project name, used as a prefix for all resources"
  type        = string
  default     = "defendarcade"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# ECR - For the execution role
# -----------------------------------------------------------------------------

variable "ecr_repository_arns" {
  description = <<-EOT
    List of ECR repository ARNs.
    The execution role will be able to pull images from these repos.
    Example: ["arn:aws:ecr:us-east-1:123456789:repository/defendarcade-backend"]
  EOT
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# CloudWatch Logs - For the execution role
# -----------------------------------------------------------------------------

variable "cloudwatch_log_group_arns" {
  description = <<-EOT
    List of CloudWatch log group ARNs.
    The execution role will be able to write container logs to them.
    Example: ["arn:aws:logs:us-east-1:123456789:log-group:/ecs/defendarcade-*"]
  EOT
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# ECS - For the backend task role
# -----------------------------------------------------------------------------

variable "ecs_cluster_arn" {
  description = <<-EOT
    ARN of the ECS cluster.
    The backend will only be able to RunTask/StopTask on this cluster.
    Example: "arn:aws:ecs:us-east-1:123456789:cluster/defendarcade"
  EOT
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Account ID - Used to build ARNs
# -----------------------------------------------------------------------------

variable "aws_account_id" {
  description = "AWS account ID (12 digits)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# S3 Assets - For the backend task role (image uploads)
# -----------------------------------------------------------------------------

variable "s3_assets_bucket_arn" {
  description = "ARN of the S3 assets bucket (for PutObject/DeleteObject)"
  type        = string
  default     = ""
}