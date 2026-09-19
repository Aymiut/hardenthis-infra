# =============================================================================
# modules/iam/outputs.tf
# =============================================================================

output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_execution_role_name" {
  description = "Name of the ECS execution role"
  value       = aws_iam_role.ecs_execution.name
}

output "lab_task_role_arn" {
  description = "ARN of the lab task role (zero AWS permissions)"
  value       = aws_iam_role.lab_task.arn
}

output "lab_task_role_name" {
  description = "Name of the lab task role"
  value       = aws_iam_role.lab_task.name
}

output "backend_task_role_arn" {
  description = "ARN of the backend task role (ECS RunTask)"
  value       = aws_iam_role.backend_task.arn
}

output "backend_task_role_name" {
  description = "Name of the backend task role"
  value       = aws_iam_role.backend_task.name
}

output "frontend_task_role_arn" {
  description = "ARN of the frontend task role (minimal)"
  value       = aws_iam_role.frontend_task.arn
}

output "frontend_task_role_name" {
  description = "Name of the frontend task role"
  value       = aws_iam_role.frontend_task.name
}

output "lab_ec2_instance_profile_name" {
  description = "Name of the Lab EC2 instance profile"
  value       = aws_iam_instance_profile.lab_ec2.name
}

output "lab_ec2_instance_profile_arn" {
  description = "ARN of the Lab EC2 instance profile"
  value       = aws_iam_instance_profile.lab_ec2.arn
}

output "traefik_instance_profile_name" {
  description = "Name of the Traefik EC2 instance profile"
  value       = aws_iam_instance_profile.traefik.name
}

output "traefik_instance_profile_arn" {
  description = "ARN of the Traefik EC2 instance profile"
  value       = aws_iam_instance_profile.traefik.arn
}

output "traefik_role_arn" {
  description = "ARN of the Traefik EC2 IAM role"
  value       = aws_iam_role.traefik.arn
}
