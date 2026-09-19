variable "name_prefix" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "private_subnet_id" {
  type = string
}

variable "traefik_sg_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "redis_endpoint" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "internal_namespace" {
  type        = string
  description = "Cloud Map namespace (e.g. defendarcade-prod.internal)"
}

variable "redis_auth_token" {
  type      = string
  sensitive = true
}
