# ---------------------------------------------------------------------------
# Traefik EC2 — Reverse proxy qui route le trafic ALB vers les services ECS
#
# Architecture : Internet -> ALB (HTTPS) -> Traefik EC2 (HTTP) -> Services ECS
#
# Routes statiques (fichier) :
#   hardenthis.com      -> frontend ECS (via Cloud Map DNS)
#   api.hardenthis.com  -> backend ECS  (via Cloud Map DNS)
#
# Routes dynamiques (Redis) :
#   lab-*.hardenthis.com -> lab ECS tasks (écrites par le backend au spawn)
# ---------------------------------------------------------------------------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "traefik" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.traefik_sg_id]
  iam_instance_profile   = var.instance_profile_name

  user_data_base64 = base64encode(templatefile("${path.module}/user_data.sh", {
    redis_endpoint     = var.redis_endpoint
    redis_auth_token   = var.redis_auth_token
    domain_name        = var.domain_name
    internal_namespace = var.internal_namespace
  }))

  tags = {
    Name = "${var.name_prefix}-traefik"
  }

  lifecycle {
    create_before_destroy = true
  }
}
