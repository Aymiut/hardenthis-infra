output "aws_region" {
  value = var.aws_region
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.labs.name
}

output "ecr_registry" {
  description = "ECR registry hostname (for ECR_REGISTRY env var)"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_labs_repo_url" {
  value = aws_ecr_repository.labs.repository_url
}

output "ecs_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "ecs_subnet_id_primary" {
  description = "Use this single subnet ID for ECS_SUBNET_ID env var"
  value       = aws_subnet.public[0].id
}

output "ecs_security_group_id" {
  value = aws_security_group.labs.id
}

output "ecs_task_role_arn" {
  value = aws_iam_role.lab_task.arn
}

output "ecs_execution_role_arn" {
  value = aws_iam_role.lab_execution.arn
}

output "lab_ec2_instance_profile_arn" {
  description = "Instance profile ARN to pass via LAB_EC2_INSTANCE_PROFILE_ARN"
  value       = aws_iam_instance_profile.lab_ec2.arn
}

output "lab_ec2_subnet_id" {
  description = "Subnet for EC2 labs (same public subnet as Fargate)"
  value       = aws_subnet.public[0].id
}

output "vpc_id" {
  description = "VPC ID — needed by Packer (PACKER_VPC_ID) to build EC2 lab AMIs"
  value       = aws_vpc.main.id
}

output "packer_subnet_id" {
  description = "Public subnet for Packer builders (alias of lab_ec2_subnet_id)"
  value       = aws_subnet.public[0].id
}

output "lab_ec2_security_group_id" {
  description = "SG for EC2 labs (same as Fargate — ttyd/gatekeeper from VPS only)"
  value       = aws_security_group.labs.id
}

output "labs_log_group" {
  value = aws_cloudwatch_log_group.labs.name
}

output "backend_iam_user_name" {
  value = aws_iam_user.backend.name
}

output "backend_aws_access_key_id" {
  description = "AWS_ACCESS_KEY_ID for the VPS .env.prod"
  value       = aws_iam_access_key.backend.id
  sensitive   = true
}

output "backend_aws_secret_access_key" {
  description = "AWS_SECRET_ACCESS_KEY for the VPS .env.prod (run: terraform output -raw backend_aws_secret_access_key)"
  value       = aws_iam_access_key.backend.secret
  sensitive   = true
}

output "labs_ci_iam_user_name" {
  value = aws_iam_user.labs_ci.name
}

output "labs_ci_aws_access_key_id" {
  description = "AWS_ACCESS_KEY_ID for the GitLab labs CI variables"
  value       = aws_iam_access_key.labs_ci.id
  sensitive   = true
}

output "labs_ci_aws_secret_access_key" {
  description = "AWS_SECRET_ACCESS_KEY for the GitLab labs CI (run: terraform output -raw labs_ci_aws_secret_access_key)"
  value       = aws_iam_access_key.labs_ci.secret
  sensitive   = true
}

output "s3_assets_bucket_name" {
  value = aws_s3_bucket.assets.id
}

output "s3_assets_bucket_url" {
  description = "Public URL prefix for assets — set as CDN_URL in the VPS .env"
  value       = "https://${aws_s3_bucket.assets.id}.s3.${var.aws_region}.amazonaws.com"
}

output "packer_builder_instance_profile_name" {
  description = "Pass to Packer with -var iam_instance_profile=<this>"
  value       = aws_iam_instance_profile.packer_builder.name
}

output "packer_builder_role_arn" {
  value = aws_iam_role.packer_builder.arn
}

output "vpce_interface_ids" {
  description = "Interface VPC endpoint IDs (ecr.api, ecr.dkr, logs) — private path for lab image pull + logs"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "vpce_s3_id" {
  description = "S3 gateway endpoint ID (free) — carries ECR layer blobs"
  value       = aws_vpc_endpoint.s3.id
}

