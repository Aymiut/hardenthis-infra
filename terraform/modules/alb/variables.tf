variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnets for the internet-facing ALB (min 2 AZs)"
}

variable "alb_sg_id" {
  type        = string
  description = "Security group ID for the ALB"
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN (hardenthis.com + *.hardenthis.com)"
}

variable "traefik_instance_id" {
  type        = string
  description = "EC2 instance ID of the Traefik reverse proxy"
}

variable "aws_account_id" {
  type        = string
  description = "AWS account ID for ALB access logs bucket policy"
}
