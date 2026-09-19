# =============================================================================
# modules/iam/main.tf — IAM roles and policies for DefendArcade
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  ecr_arns = length(var.ecr_repository_arns) > 0 ? var.ecr_repository_arns : ["*"]

  log_group_arns = length(var.cloudwatch_log_group_arns) > 0 ? [
    for arn in var.cloudwatch_log_group_arns :
    endswith(arn, ":*") ? arn : "${arn}:*"
  ] : ["*"]

  log_group_arns_base = length(var.cloudwatch_log_group_arns) > 0 ? [
    for arn in var.cloudwatch_log_group_arns :
    endswith(arn, ":*") ? trimsuffix(arn, ":*") : arn
  ] : ["*"]

  common_tags = merge(var.tags, {
    Module = "iam"
  })
}

# ---------------------------------------------------------------------------
# Trust policies
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_task_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# =============================================================================
# ROLE 1: ECS Execution Role
# Used by the ECS agent BEFORE containers start.
# Pulls images from ECR, writes logs to CloudWatch, reads Secrets Manager.
# =============================================================================

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-execution"
    Role = "ecs-execution"
  })
}

data "aws_iam_policy_document" "ecs_execution" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = local.ecr_arns
  }

  statement {
    sid       = "CloudWatchCreateGroup"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = local.log_group_arns_base
  }

  statement {
    sid    = "CloudWatchWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = local.log_group_arns
  }

  # Read secrets injected into ECS task definitions
  statement {
    sid    = "SecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${local.name_prefix}/*",
    ]
  }
}

resource "aws_iam_policy" "ecs_execution" {
  name   = "${local.name_prefix}-ecs-execution"
  policy = data.aws_iam_policy_document.ecs_execution.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = aws_iam_policy.ecs_execution.arn
}

# =============================================================================
# ROLE 2: Lab Task Role
# Used by lab containers at RUNTIME. Zero AWS permissions (isolation).
# =============================================================================

resource "aws_iam_role" "lab_task" {
  name               = "${local.name_prefix}-lab-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lab-task"
    Role = "lab-task"
  })
}

# No policy attached = zero AWS permissions

# =============================================================================
# ROLE 3: Backend Task Role
# Used by NestJS at RUNTIME: launches/stops ECS lab tasks.
# =============================================================================

resource "aws_iam_role" "backend_task" {
  name               = "${local.name_prefix}-backend-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-backend-task"
    Role = "backend-task"
  })
}

data "aws_iam_policy_document" "backend_task" {
  # RegisterTaskDefinition and DescribeTaskDefinition cannot be scoped by resource
  statement {
    sid    = "ECSRegisterTaskDef"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECSRunTask"
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "ecs:TagResource",
    ]
    resources = [
      var.ecs_cluster_arn != "" ? "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:task-definition/lab-*" : "*",
      var.ecs_cluster_arn != "" ? "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:task/*" : "*",
    ]
  }

  statement {
    sid    = "ECSStopAndDescribe"
    effect = "Allow"
    actions = [
      "ecs:StopTask",
      "ecs:DescribeTasks",
    ]
    resources = [
      var.ecs_cluster_arn != "" ? "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:task/*" : "*",
    ]
  }

  # ListTasks cannot be scoped by resource
  statement {
    sid       = "ECSListTasks"
    effect    = "Allow"
    actions   = ["ecs:ListTasks"]
    resources = ["*"]
  }

  # --- EC2 permissions for EC2-based labs ---
  # Resources CREATED and tagged during RunInstances
  statement {
    sid    = "EC2RunInstancesTagged"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
    ]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:volume/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:network-interface/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/ManagedBy"
      values   = ["hardenthis"]
    }
  }

  # Pre-existing resources referenced during RunInstances (no tags in request)
  statement {
    sid    = "EC2RunInstancesExisting"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
    ]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:security-group/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:subnet/*",
      "arn:aws:ec2:${var.aws_region}::image/*",
    ]
  }

  statement {
    sid    = "EC2CreateTags"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
    ]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:volume/*",
      "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:network-interface/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances"]
    }
  }

  statement {
    sid    = "EC2TerminateAndDescribe"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DescribeInstances",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/ManagedBy"
      values   = ["hardenthis"]
    }
  }

  statement {
    sid       = "EC2DescribeGlobal"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  # PassRole scoped to execution + lab task + lab EC2 roles
  statement {
    sid     = "PassRoleToECS"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution.arn,
      aws_iam_role.lab_task.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid     = "PassRoleToEC2"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.lab_ec2.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # --- S3 permissions for image uploads ---
  dynamic "statement" {
    for_each = var.s3_assets_bucket_arn != "" ? [1] : []
    content {
      sid    = "S3AssetsUpload"
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:DeleteObject",
      ]
      resources = ["${var.s3_assets_bucket_arn}/*"]
    }
  }

  statement {
    sid       = "CloudWatchCreateGroup"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup"]
    resources = local.log_group_arns_base
  }

  statement {
    sid    = "CloudWatchWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = local.log_group_arns
  }
}

resource "aws_iam_policy" "backend_task" {
  name   = "${local.name_prefix}-backend-task"
  policy = data.aws_iam_policy_document.backend_task.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backend_task" {
  role       = aws_iam_role.backend_task.name
  policy_arn = aws_iam_policy.backend_task.arn
}

# =============================================================================
# ROLE 4: Frontend Task Role
# Next.js has no AWS SDK calls — minimal role with CloudWatch logs only.
# =============================================================================

resource "aws_iam_role" "frontend_task" {
  name               = "${local.name_prefix}-frontend-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-frontend-task"
    Role = "frontend-task"
  })
}

# No inline policy needed — CloudWatch logs are written via the execution role (awslogs driver)

# =============================================================================
# ROLE 5: Lab EC2 Instance Role + Instance Profile
# Used by EC2-based lab instances at RUNTIME. Zero AWS permissions (isolation).
# =============================================================================

resource "aws_iam_role" "lab_ec2" {
  name               = "${local.name_prefix}-lab-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lab-ec2"
    Role = "lab-ec2"
  })
}

# No policy attached = zero AWS permissions (same as lab_task for ECS)

resource "aws_iam_instance_profile" "lab_ec2" {
  name = "${local.name_prefix}-lab-ec2"
  role = aws_iam_role.lab_ec2.name
  tags = local.common_tags
}

# =============================================================================
# ROLE 6: Traefik EC2 Role + Instance Profile
# EC2 instance running Traefik — SSM Session Manager (no SSH key needed).
# =============================================================================

resource "aws_iam_role" "traefik" {
  name               = "${local.name_prefix}-traefik"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-traefik"
    Role = "traefik"
  })
}

resource "aws_iam_role_policy_attachment" "traefik_ssm" {
  role       = aws_iam_role.traefik.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "traefik" {
  name = "${local.name_prefix}-traefik"
  role = aws_iam_role.traefik.name
  tags = local.common_tags
}
