# modules/acm/main.tf
# ACM certificate for the primary domain + wildcard (lab subdomains).
# DNS validation done manually via Cloudflare (no Route53 needed).

resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = var.domain_name
  }
}

# No Route53 validation — the user creates CNAME records on Cloudflare manually.
# Terraform outputs the required DNS records.
