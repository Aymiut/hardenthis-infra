# RDS PostgreSQL security group
# Redis has its own SG (redis.tf) — this file is PostgreSQL-only.

resource "aws_security_group" "db" {
  vpc_id      = var.vpc_id
  name        = "db"
  description = "Security group for RDS PostgreSQL"

  tags = {
    Name = "db"
  }
}

# Only the backend ECS tasks need direct PostgreSQL access
resource "aws_vpc_security_group_ingress_rule" "db_from_backend" {
  security_group_id            = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend.id
  description                  = "PostgreSQL access from NestJS backend ECS tasks"
}

# Traefik EC2 needs DB access for SSM port-forwarding (migrations, debugging)
resource "aws_vpc_security_group_ingress_rule" "db_from_traefik" {
  security_group_id            = aws_security_group.db.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.traefik.id
  description                  = "PostgreSQL access from Traefik EC2 (SSM port forwarding)"
}
