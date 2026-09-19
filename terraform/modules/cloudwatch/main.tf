resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.name_prefix}-backend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.name_prefix}-frontend"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "labs" {
  name              = "/ecs/${var.name_prefix}-labs"
  retention_in_days = 30
}
