output "database_url_secret_arn" {
  value = aws_secretsmanager_secret.database_url.arn
}

output "jwt_access_secret_arn" {
  value = aws_secretsmanager_secret.jwt_access.arn
}

output "jwt_refresh_secret_arn" {
  value = aws_secretsmanager_secret.jwt_refresh.arn
}

output "admin_sync_secret_arn" {
  value = aws_secretsmanager_secret.admin_sync.arn
}
