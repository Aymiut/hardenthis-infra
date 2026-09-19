output "endpoints_sg_id" {
  description = "Security group ID attached to the interface VPC endpoints"
  value       = aws_security_group.endpoints.id
}

output "s3_prefix_list_id" {
  description = "Prefix list ID of the S3 gateway endpoint"
  value       = aws_vpc_endpoint.s3.prefix_list_id
}
