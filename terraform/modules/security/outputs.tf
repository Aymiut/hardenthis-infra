output "alb_sg_id" {
  description = "ID of the ALB Security Group"
  value       = aws_security_group.alb.id
}

output "traefik_sg_id" {
  description = "ID of the Traefik Security Group"
  value       = aws_security_group.traefik.id
}

output "frontend_sg_id" {
  description = "ID of the Frontend ECS Security Group"
  value       = aws_security_group.frontend.id
}

output "backend_sg_id" {
  description = "ID of the Backend ECS Security Group"
  value       = aws_security_group.backend.id
}

output "redis_sg_id" {
  description = "ID of the ElastiCache Redis Security Group"
  value       = aws_security_group.redis.id
}

output "db_sg_id" {
  description = "ID of the RDS PostgreSQL Security Group"
  value       = aws_security_group.db.id
}

output "labs_sg_id" {
  description = "ID of the Labs ECS Security Group"
  value       = aws_security_group.labs.id
}
