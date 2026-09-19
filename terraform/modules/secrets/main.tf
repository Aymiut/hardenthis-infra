resource "aws_secretsmanager_secret" "database_url" {
  name                    = "${var.name_prefix}/database-url"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${var.db_username}:${var.db_password}@${var.db_endpoint}:5432/${var.db_name}?schema=public"
}

resource "aws_secretsmanager_secret" "jwt_access" {
  name                    = "${var.name_prefix}/jwt-access-secret"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "jwt_access" {
  secret_id     = aws_secretsmanager_secret.jwt_access.id
  secret_string = var.jwt_access_secret
}

resource "aws_secretsmanager_secret" "jwt_refresh" {
  name                    = "${var.name_prefix}/jwt-refresh-secret"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "jwt_refresh" {
  secret_id     = aws_secretsmanager_secret.jwt_refresh.id
  secret_string = var.jwt_refresh_secret
}

resource "aws_secretsmanager_secret" "admin_sync" {
  name                    = "${var.name_prefix}/admin-sync-secret"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "admin_sync" {
  secret_id     = aws_secretsmanager_secret.admin_sync.id
  secret_string = var.admin_sync_secret
}
