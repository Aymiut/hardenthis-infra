# infra/terraform/outputs.tf

output "alb_dns_name" {
  description = "Public DNS name of the ALB — point your Cloudflare CNAME records here"
  value       = module.alb.alb_dns_name
}

output "acm_validation_records" {
  description = "DNS records to create on Cloudflare for ACM certificate validation"
  value       = module.acm.validation_records
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = module.elasticache.redis_endpoint
  sensitive   = true
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = module.ecs.cluster_arn
}

output "traefik_instance_id" {
  description = "Traefik EC2 instance ID"
  value       = module.traefik.instance_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.network.public_subnet_ids
}

output "s3_assets_bucket_domain" {
  description = "S3 assets bucket domain — use as Cloudflare CNAME target for cdn.<domain>"
  value       = module.s3_assets.bucket_regional_domain
}
