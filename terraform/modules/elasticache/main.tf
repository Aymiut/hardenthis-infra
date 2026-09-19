resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.name_prefix}-redis"
  family = "redis7"

  # Enable keyspace notifications for Traefik to detect new/changed routes
  parameter {
    name  = "notify-keyspace-events"
    value = "KEA"
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis for ${var.name_prefix}"

  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t3.micro"
  num_cache_clusters   = 1
  parameter_group_name = aws_elasticache_parameter_group.this.name

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.redis_sg_id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  auth_token                 = var.redis_auth_token
  apply_immediately          = true

  port = 6379

  tags = { Name = "${var.name_prefix}-redis" }
}
