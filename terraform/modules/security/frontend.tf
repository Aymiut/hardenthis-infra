# Frontend ECS Fargate security group (Next.js, port 3001)

resource "aws_security_group" "frontend" {
  vpc_id      = var.vpc_id
  name        = "frontend"
  description = "Security group for the Next.js frontend ECS tasks"

  tags = {
    Name = "frontend"
  }
}

# Traefik forwards requests to the frontend on port 3001
resource "aws_vpc_security_group_ingress_rule" "frontend_from_traefik" {
  security_group_id            = aws_security_group.frontend.id
  from_port                    = 3001
  to_port                      = 3001
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.traefik.id
  description                  = "Allow inbound traffic from Traefik on port 3001 (Next.js)"
}

# Frontend needs HTTPS to reach public APIs (api.hardenthis.com through ALB)
resource "aws_vpc_security_group_egress_rule" "frontend_to_https" {
  security_group_id = aws_security_group.frontend.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS egress for API calls and ECR image pulls"
}

resource "aws_vpc_security_group_egress_rule" "frontend_to_dns_udp" {
  security_group_id = aws_security_group.frontend.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "10.0.0.0/16"
  description       = "DNS resolution via VPC resolver (UDP)"
}

resource "aws_vpc_security_group_egress_rule" "frontend_to_dns_tcp" {
  security_group_id = aws_security_group.frontend.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"
  description       = "DNS resolution via VPC resolver (TCP)"
}
