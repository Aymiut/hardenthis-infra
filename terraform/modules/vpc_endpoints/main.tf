# VPC endpoints that allow ECS Fargate lab tasks to pull images from ECR and
# ship logs to CloudWatch *without* going to the public internet via NAT.
#
# Together with the locked-down lab security group (see modules/security/labs.tf),
# this severs all outbound internet access from lab containers — only ECR, S3
# (for ECR layer storage) and CloudWatch Logs remain reachable.

# ---------------------------------------------------------------------------
# Security group for the interface endpoints
# ---------------------------------------------------------------------------
# Endpoint ENIs sit in the VPC and need to accept 443 from anything that talks
# to AWS APIs through them. Today that's the labs; backend/frontend can be
# wired up later if we want to drop their NAT dependency too.

resource "aws_security_group" "endpoints" {
  vpc_id      = var.vpc_id
  name        = "vpc-endpoints"
  description = "Interface VPC endpoints (ECR + CloudWatch Logs)"

  tags = {
    Name = "vpc-endpoints"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_labs" {
  security_group_id            = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.labs_sg_id
  description                  = "HTTPS from lab tasks for ECR/Logs API calls"
}

# Backend/frontend/traefik must also be allowed: with private DNS enabled on
# the endpoints, the public DNS names of ECR & Logs resolve to these endpoints
# VPC-wide, so every workload that talks to those services has to come through.

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_backend" {
  security_group_id            = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.backend_sg_id
  description                  = "HTTPS from backend ECS (ECR pulls + CloudWatch Logs)"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_frontend" {
  security_group_id            = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.frontend_sg_id
  description                  = "HTTPS from frontend ECS (ECR pulls + CloudWatch Logs)"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_traefik" {
  security_group_id            = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.traefik_sg_id
  description                  = "HTTPS from Traefik EC2 (CloudWatch Logs / agent)"
}

# ---------------------------------------------------------------------------
# Interface endpoints — used by the Fargate platform to pull lab images and
# stream lab stdout/stderr to CloudWatch. Without these, blocking internet
# egress would prevent labs from ever starting.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "ecr-api" }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "ecr-dkr" }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "logs" }
}

# ---------------------------------------------------------------------------
# S3 gateway endpoint — ECR stores image layers in S3, so layer downloads
# during `docker pull` need an S3 route. Gateway endpoints are free and
# routed via the route table rather than via an ENI.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = { Name = "s3" }
}

# ---------------------------------------------------------------------------
# Lab → endpoint egress rules
# ---------------------------------------------------------------------------
# Defined here (not in modules/security) so the lab SG can reference the
# endpoint SG without creating a module dependency cycle.

resource "aws_vpc_security_group_egress_rule" "labs_to_endpoints" {
  security_group_id            = var.labs_sg_id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.endpoints.id
  description                  = "HTTPS to ECR/Logs interface VPC endpoints"
}

resource "aws_vpc_security_group_egress_rule" "labs_to_s3" {
  security_group_id = var.labs_sg_id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  description       = "HTTPS to S3 gateway endpoint (ECR layer storage)"
}
