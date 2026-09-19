variable "name_prefix" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

# --- Images ---

variable "backend_image" {
  type = string
}

variable "frontend_image" {
  type = string
}

# --- Security Groups ---

variable "backend_sg_id" {
  type = string
}

variable "frontend_sg_id" {
  type = string
}

variable "labs_sg_id" {
  type = string
}

# --- IAM ---

variable "ecs_execution_role_arn" {
  type = string
}

variable "backend_task_role_arn" {
  type = string
}

variable "frontend_task_role_arn" {
  type = string
}

variable "lab_task_role_arn" {
  type = string
}

# --- Runtime config ---

variable "redis_endpoint" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "frontend_url" {
  type = string
}

variable "labs_subnet_id" {
  type = string
}

variable "labs_sg_id_for_tasks" {
  type = string
}

# --- EC2 Lab config ---

variable "lab_ec2_instance_profile_arn" {
  description = "ARN of the IAM instance profile for EC2 labs"
  type        = string
  default     = ""
}

variable "lab_ec2_instance_type" {
  description = "EC2 instance type for labs"
  type        = string
  default     = "t3.micro"
}

# --- Secrets ARNs ---

variable "database_url_secret_arn" {
  type = string
}

variable "jwt_access_secret_arn" {
  type = string
}

variable "jwt_refresh_secret_arn" {
  type = string
}

variable "admin_sync_secret_arn" {
  type = string
}

variable "terminal_secret" {
  type      = string
  sensitive = true
}

variable "redis_auth_token" {
  type      = string
  sensitive = true
}

# --- S3 Assets ---

variable "s3_assets_bucket" {
  description = "S3 bucket name for image assets"
  type        = string
  default     = ""
}

variable "cdn_url" {
  description = "CDN URL for serving images (e.g. https://cdn.hardenthis.com)"
  type        = string
  default     = ""
}

# --- Log groups ---

variable "backend_log_group_name" {
  type = string
}

variable "frontend_log_group_name" {
  type = string
}

