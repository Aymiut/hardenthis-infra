variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "aws_region" {
  description = "AWS region (used to build the endpoint service names)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets in which to deploy interface endpoint ENIs (must cover the AZs where labs run)"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Route tables to associate with the S3 gateway endpoint"
  type        = list(string)
}

variable "labs_sg_id" {
  description = "Security group of the lab tasks — gets egress rules added pointing at the endpoints"
  type        = string
}

# private_dns_enabled = true on the interface endpoints hijacks ECR/Logs DNS
# resolution VPC-wide. Any workload that reaches those services must therefore
# be allowed into the endpoints SG, not just the labs.

variable "backend_sg_id" {
  description = "Backend ECS task SG (ECR image pulls, CloudWatch Logs via endpoint)"
  type        = string
}

variable "frontend_sg_id" {
  description = "Frontend ECS task SG (ECR image pulls, CloudWatch Logs via endpoint)"
  type        = string
}

variable "traefik_sg_id" {
  description = "Traefik EC2 SG (CloudWatch Logs / agent via endpoint)"
  type        = string
}
