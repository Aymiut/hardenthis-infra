# Labs ECS Fargate security group
# Lab containers are ephemeral, isolated, and only accessible via Traefik (ttyd)
# and the backend (gatekeeper validation on port 9999).

resource "aws_security_group" "labs" {
  vpc_id      = var.vpc_id
  name        = "labs"
  description = "Security group for ephemeral lab ECS tasks (ttyd + gatekeeper)"

  tags = {
    Name = "labs"
  }
}

# Traefik proxies the ttyd web terminal to the user's browser
resource "aws_vpc_security_group_ingress_rule" "labs_from_traefik_ttyd" {
  security_group_id            = aws_security_group.labs.id
  from_port                    = 7681
  to_port                      = 7681
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.traefik.id
  description                  = "ttyd web terminal from Traefik"
}

# Traefik may also proxy lab HTTP services (e.g. web challenges)
resource "aws_vpc_security_group_ingress_rule" "labs_from_traefik_http" {
  security_group_id            = aws_security_group.labs.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.traefik.id
  description                  = "Lab HTTP service from Traefik"
}

# Backend calls the gatekeeper HTTP endpoint for validation
resource "aws_vpc_security_group_ingress_rule" "labs_from_backend_gatekeeper" {
  security_group_id            = aws_security_group.labs.id
  from_port                    = 9999
  to_port                      = 9999
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend.id
  description                  = "Gatekeeper validation from backend (HTTP GET :9999/validate)"
}

# Labs need internet egress for apt, pip installs at challenge runtime
resource "aws_vpc_security_group_egress_rule" "labs_to_internet_https" {
  security_group_id = aws_security_group.labs.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS egress for package downloads and ECR image pulls"
}

resource "aws_vpc_security_group_egress_rule" "labs_to_internet_http" {
  security_group_id = aws_security_group.labs.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTP egress for package downloads (apt, pip)"
}

resource "aws_vpc_security_group_egress_rule" "labs_to_dns_udp" {
  security_group_id = aws_security_group.labs.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "10.0.0.0/16"
  description       = "DNS resolution via VPC resolver (UDP)"
}

resource "aws_vpc_security_group_egress_rule" "labs_to_dns_tcp" {
  security_group_id = aws_security_group.labs.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/16"
  description       = "DNS resolution via VPC resolver (TCP)"
}
