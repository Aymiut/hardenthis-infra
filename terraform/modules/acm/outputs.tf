output "certificate_arn" {
  description = "ARN of the ACM certificate (may not be validated yet)"
  value       = aws_acm_certificate.main.arn
}

output "validation_records" {
  description = "DNS records to create on Cloudflare for certificate validation"
  value = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}
