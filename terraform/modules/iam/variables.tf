# =============================================================================
# variables.tf - Inputs du module IAM
# =============================================================================

# -----------------------------------------------------------------------------
# Général
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Nom du projet, utilisé comme préfixe pour toutes les ressources"
  type        = string
  default     = "defendarcade"
}

variable "environment" {
  description = "Environnement (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags à appliquer à toutes les ressources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# ECR - Pour l'execution role
# -----------------------------------------------------------------------------

variable "ecr_repository_arns" {
  description = <<-EOT
    Liste des ARN des repositories ECR.
    L'execution role pourra pull les images depuis ces repos.
    Exemple: ["arn:aws:ecr:us-east-1:123456789:repository/defendarcade-backend"]
  EOT
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# CloudWatch Logs - Pour l'execution role
# -----------------------------------------------------------------------------

variable "cloudwatch_log_group_arns" {
  description = <<-EOT
    Liste des ARN des log groups CloudWatch.
    L'execution role pourra y écrire les logs des conteneurs.
    Exemple: ["arn:aws:logs:us-east-1:123456789:log-group:/ecs/defendarcade-*"]
  EOT
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# ECS - Pour le backend task role
# -----------------------------------------------------------------------------

variable "ecs_cluster_arn" {
  description = <<-EOT
    ARN du cluster ECS.
    Le backend pourra RunTask/StopTask uniquement sur ce cluster.
    Exemple: "arn:aws:ecs:us-east-1:123456789:cluster/defendarcade"
  EOT
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Account ID - Pour construire les ARN
# -----------------------------------------------------------------------------

variable "aws_account_id" {
  description = "ID du compte AWS (12 chiffres)"
  type        = string
}

variable "aws_region" {
  description = "Région AWS"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# S3 Assets - Pour le backend task role (upload images)
# -----------------------------------------------------------------------------

variable "s3_assets_bucket_arn" {
  description = "ARN du bucket S3 assets (pour PutObject/DeleteObject)"
  type        = string
  default     = ""
}