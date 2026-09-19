# ALB security group — internet-facing entrypoint
# Accepts HTTP (for redirect) and HTTPS from the internet.
# Forwards to Traefik on port 80 only (ALB terminates TLS).

resource "aws_security_group" "alb" {
  vpc_id      = var.vpc_id
  name        = "alb"
  description = "Security group for the internet-facing Application Load Balancer"

  tags = {
    Name = "alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTP from internet (redirected to HTTPS by ALB listener)"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS from internet (TLS terminated at ALB)"
}

# ALB forwards HTTP to Traefik (TLS is terminated at ALB, Traefik sees plain HTTP)
resource "aws_vpc_security_group_egress_rule" "alb_to_traefik" {
  security_group_id            = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.traefik.id
  description                  = "Forward HTTP to Traefik reverse proxy"
}
