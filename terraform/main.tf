# infra/terraform/main.tf

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Network (VPC, subnets, IGW, NAT GW, route tables)
# ---------------------------------------------------------------------------

module "network" {
  source = "./modules/network"
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

module "security" {
  source = "./modules/security"
  vpc_id = module.network.vpc_id
}

# ---------------------------------------------------------------------------
# IAM roles & instance profiles
# ---------------------------------------------------------------------------

module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region

  ecr_repository_arns = module.ecr.repository_arns

  cloudwatch_log_group_arns = [
    "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/ecs/${local.name_prefix}-*",
  ]

  ecs_cluster_arn = module.ecs.cluster_arn

  s3_assets_bucket_arn = module.s3_assets.bucket_arn

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# S3 assets bucket (images: labs, courses, users)
# ---------------------------------------------------------------------------

module "s3_assets" {
  source = "./modules/s3-assets"

  name_prefix = local.name_prefix
  domain_name = var.domain_name
}

# ---------------------------------------------------------------------------
# ECR repositories
# ---------------------------------------------------------------------------

module "ecr" {
  source = "./modules/ecr"

  repository_names = [
    "defendarcade/backend",
    "defendarcade/frontend",
    "defendarcade/labs",
  ]
}

# ---------------------------------------------------------------------------
# ACM certificate (hardenthis.com + *.hardenthis.com)
# ---------------------------------------------------------------------------

module "acm" {
  source = "./modules/acm"

  domain_name = var.domain_name
}

# ---------------------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------------------

module "alb" {
  source = "./modules/alb"

  name_prefix         = local.name_prefix
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  alb_sg_id           = module.security.alb_sg_id
  certificate_arn     = module.acm.certificate_arn
  traefik_instance_id = module.traefik.instance_id
  aws_account_id      = var.aws_account_id
}

# ---------------------------------------------------------------------------
# RDS PostgreSQL
# ---------------------------------------------------------------------------

module "rds" {
  source = "./modules/rds"

  name_prefix        = local.name_prefix
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
  private_subnet_ids = module.network.private_subnet_ids
  db_sg_id           = module.security.db_sg_id
}

# ---------------------------------------------------------------------------
# ElastiCache Redis
# ---------------------------------------------------------------------------

module "elasticache" {
  source = "./modules/elasticache"

  name_prefix        = local.name_prefix
  private_subnet_ids = module.network.private_subnet_ids
  redis_sg_id        = module.security.redis_sg_id
  redis_auth_token   = var.redis_auth_token
}

# ---------------------------------------------------------------------------
# Secrets Manager
# ---------------------------------------------------------------------------

module "secrets" {
  source = "./modules/secrets"

  name_prefix        = local.name_prefix
  db_username        = var.db_username
  db_password        = var.db_password
  db_name            = var.db_name
  db_endpoint        = module.rds.db_endpoint
  jwt_access_secret  = var.jwt_access_secret
  jwt_refresh_secret = var.jwt_refresh_secret
  admin_sync_secret  = var.admin_sync_secret
}

# ---------------------------------------------------------------------------
# CloudWatch log groups
# ---------------------------------------------------------------------------

module "cloudwatch" {
  source = "./modules/cloudwatch"

  name_prefix = local.name_prefix
}

# ---------------------------------------------------------------------------
# ECS cluster + services (backend, frontend)
# ---------------------------------------------------------------------------

module "ecs" {
  source = "./modules/ecs"

  name_prefix        = local.name_prefix
  aws_region         = var.aws_region
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  # Images
  backend_image  = var.ecr_backend_image
  frontend_image = var.ecr_frontend_image

  # Security groups
  backend_sg_id  = module.security.backend_sg_id
  frontend_sg_id = module.security.frontend_sg_id
  labs_sg_id     = module.security.labs_sg_id

  # IAM
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
  backend_task_role_arn  = module.iam.backend_task_role_arn
  frontend_task_role_arn = module.iam.frontend_task_role_arn
  lab_task_role_arn      = module.iam.lab_task_role_arn

  # Runtime config
  redis_endpoint       = module.elasticache.redis_endpoint
  redis_auth_token     = var.redis_auth_token
  domain_name          = var.domain_name
  frontend_url         = "https://${var.domain_name}"
  labs_subnet_id       = module.network.private_subnet_ids[0]
  labs_sg_id_for_tasks = module.security.labs_sg_id

  # EC2 lab config
  lab_ec2_instance_profile_arn = module.iam.lab_ec2_instance_profile_arn
  lab_ec2_instance_type        = "t3.micro"

  # S3 assets (image uploads)
  s3_assets_bucket = module.s3_assets.bucket_name
  cdn_url          = "https://cdn.${var.domain_name}"

  # Secrets
  terminal_secret         = var.terminal_secret
  database_url_secret_arn = module.secrets.database_url_secret_arn
  jwt_access_secret_arn   = module.secrets.jwt_access_secret_arn
  jwt_refresh_secret_arn  = module.secrets.jwt_refresh_secret_arn
  admin_sync_secret_arn   = module.secrets.admin_sync_secret_arn

  # Log groups
  backend_log_group_name  = module.cloudwatch.backend_log_group_name
  frontend_log_group_name = module.cloudwatch.frontend_log_group_name

  depends_on = [module.rds, module.elasticache, module.secrets, module.cloudwatch]
}

# ---------------------------------------------------------------------------
# Traefik EC2 (reverse proxy, reads Redis, routes to ECS tasks)
# ---------------------------------------------------------------------------

module "traefik" {
  source = "./modules/traefik"

  name_prefix           = local.name_prefix
  instance_type         = var.traefik_instance_type
  private_subnet_id     = module.network.private_subnet_ids[0]
  traefik_sg_id         = module.security.traefik_sg_id
  instance_profile_name = module.iam.traefik_instance_profile_name
  redis_endpoint        = module.elasticache.redis_endpoint
  redis_auth_token      = var.redis_auth_token
  domain_name           = var.domain_name
  internal_namespace    = "${local.name_prefix}.internal"
}
