# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.name_prefix}-cluster" }
}

# ---------------------------------------------------------------------------
# Cloud Map namespace (service discovery interne)
# Permet aux services de se trouver via DNS :
#   backend  -> backend.defendarcade-prod.internal
#   frontend -> frontend.defendarcade-prod.internal
# ---------------------------------------------------------------------------

resource "aws_service_discovery_private_dns_namespace" "this" {
  name = "${var.name_prefix}.internal"
  vpc  = var.vpc_id
}
