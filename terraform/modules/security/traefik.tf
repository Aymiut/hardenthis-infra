# Traefik EC2 security group — private reverse proxy behind the ALB.
# No direct internet access. Only the ALB may push HTTP traffic in.

resource "aws_security_group" "traefik" {
  vpc_id      = var.vpc_id
  name        = "traefik"
  description = "Security group for Traefik EC2 reverse proxy (private, behind ALB)"

  tags = {
    Name = "traefik"
  }
}

# ALB forwards HTTP (TLS already terminated) to Traefik on port 80
resource "aws_vpc_security_group_ingress_rule" "traefik_from_alb" {
  security_group_id            = aws_security_group.traefik.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "HTTP from ALB (TLS terminated at ALB)"
}

# Traefik forwards to the Next.js frontend
resource "aws_vpc_security_group_egress_rule" "traefik_to_frontend" {
  security_group_id            = aws_security_group.traefik.id
  from_port                    = 3001
  to_port                      = 3001
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.frontend.id
  description                  = "Forward to Next.js frontend ECS tasks on port 3001"
}

# Traefik forwards to the NestJS backend
resource "aws_vpc_security_group_egress_rule" "traefik_to_backend" {
  security_group_id            = aws_security_group.traefik.id
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend.id
  description                  = "Forward to NestJS backend ECS tasks on port 3000"
}

# Traefik forwards to lab containers (ttyd web terminal)
resource "aws_vpc_security_group_egress_rule" "traefik_to_labs_ttyd" {
  security_group_id            = aws_security_group.traefik.id
  from_port                    = 7681
  to_port                      = 7681
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.labs.id
  description                  = "Forward to lab ttyd terminal on port 7681"
}

# Traefik forwards to lab HTTP services (used by some labs)
resource "aws_vpc_security_group_egress_rule" "traefik_to_labs_http" {
  security_group_id            = aws_security_group.traefik.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.labs.id
  description                  = "Forward to lab HTTP service on port 8080"
}

# Traefik reads dynamic routing keys from ElastiCache Redis
resource "aws_vpc_security_group_egress_rule" "traefik_to_redis" {
  security_group_id            = aws_security_group.traefik.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.redis.id
  description                  = "Read Traefik dynamic routing keys from ElastiCache Redis"
}

# SSM port forwarding to RDS (for migrations / debugging)
resource "aws_vpc_security_group_egress_rule" "traefik_to_db" {
  security_group_id            = aws_security_group.traefik.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.db.id
  description                  = "PostgreSQL access via SSM port forwarding"
}

# Docker Hub / ECR pulls, SSM agent, CloudWatch agent
resource "aws_vpc_security_group_egress_rule" "traefik_to_https" {
  security_group_id = aws_security_group.traefik.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS egress for Traefik image pulls and SSM"
}

resource "aws_vpc_security_group_egress_rule" "traefik_to_dns_udp" {
  security_group_id = aws_security_group.traefik.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "10.0.0.0/16"
  description       = "DNS resolution via VPC resolver (UDP)"
}

resource "aws_vpc_security_group_egress_rule" "traefik_to_dns_tcp" {
  security_group_id = aws_security_group.traefik.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"
  description       = "DNS resolution via VPC resolver (TCP)"
}
