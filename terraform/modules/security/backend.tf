# Backend ECS Fargate security group (NestJS, port 3000)

resource "aws_security_group" "backend" {
  vpc_id      = var.vpc_id
  name        = "backend"
  description = "Security group for NestJS backend ECS tasks"

  tags = {
    Name = "backend"
  }
}

# Traefik forwards api.hardenthis.com requests to the backend
resource "aws_vpc_security_group_ingress_rule" "backend_from_traefik" {
  security_group_id            = aws_security_group.backend.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.traefik.id
  description                  = "HTTP from Traefik reverse proxy"
}

# Backend connects to RDS PostgreSQL
resource "aws_vpc_security_group_egress_rule" "backend_to_postgresql" {
  security_group_id            = aws_security_group.backend.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.db.id
  description                  = "PostgreSQL access to RDS"
}

# Backend connects to ElastiCache Redis (Traefik routing + cache)
resource "aws_vpc_security_group_egress_rule" "backend_to_redis" {
  security_group_id            = aws_security_group.backend.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.redis.id
  description                  = "Redis access to ElastiCache (Traefik routing keys + cache)"
}

# Backend calls gatekeeper in lab containers for validation
resource "aws_vpc_security_group_egress_rule" "backend_to_labs_gatekeeper" {
  security_group_id            = aws_security_group.backend.id
  from_port                    = 9999
  to_port                      = 9999
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.labs.id
  description                  = "HTTP to lab gatekeeper for validation (GET :9999/validate)"
}

# ECS API, ECR, CloudWatch, Secrets Manager — all over HTTPS
resource "aws_vpc_security_group_egress_rule" "backend_to_aws_apis" {
  security_group_id = aws_security_group.backend.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS egress to AWS APIs (ECS, ECR, CloudWatch, Secrets Manager)"
}

resource "aws_vpc_security_group_egress_rule" "backend_to_dns_udp" {
  security_group_id = aws_security_group.backend.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "10.0.0.0/16"
  description       = "DNS resolution via VPC resolver (UDP)"
}

resource "aws_vpc_security_group_egress_rule" "backend_to_dns_tcp" {
  security_group_id = aws_security_group.backend.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"
  description       = "DNS resolution via VPC resolver (TCP)"
}
