# Redis (ElastiCache) security group
# Separate from the RDS SG for clarity and least-privilege.
# Clients: backend ECS tasks (dynamic routing writes) + Traefik EC2 (reads routing table).

resource "aws_security_group" "redis" {
  vpc_id      = var.vpc_id
  name        = "redis"
  description = "Security group for ElastiCache Redis (Traefik dynamic routing + backend cache)"

  tags = {
    Name = "redis"
  }
}

# Backend writes Traefik routes and session data to Redis
resource "aws_vpc_security_group_ingress_rule" "redis_from_backend" {
  security_group_id            = aws_security_group.redis.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend.id
  description                  = "Backend ECS tasks write Traefik routing keys and cache"
}

# Traefik reads dynamic routing rules from Redis
resource "aws_vpc_security_group_ingress_rule" "redis_from_traefik" {
  security_group_id            = aws_security_group.redis.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.traefik.id
  description                  = "Traefik EC2 reads dynamic lab routing rules from Redis"
}
