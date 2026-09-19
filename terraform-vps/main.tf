# Minimal AWS infra for VPS-hybrid deployment.
# Only labs run on AWS now — the site (front/back/db/redis) lives on the VPS.
#
# Resources kept on AWS:
#   - VPC + public subnets (no NAT, labs get public IPs directly)
#   - Security group for lab tasks (ingress restricted to VPS public IP)
#   - ECR repo for lab images
#   - CloudWatch log group for lab logs
#   - IAM roles: execution (ECR pull + logs), lab task role (zero perms)
#   - ECS cluster (Fargate-only, no permanent services)
#
# The old all-AWS stack (`terraform/`) has been destroyed and is kept for
# reference only. See README.md.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "hardenthis-terraform-state"
    key            = "vps-hybrid/terraform.tfstate"
    region         = "us-east-1" # state bucket stays where it is
    dynamodb_table = "hardenthis-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "vps-hybrid"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# VPC + 2 public subnets (no NAT — labs use public IPs)
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name_prefix}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security group: lab tasks
# Strict: ingress only from VPS public IP, no SMTP/SSH egress
# ---------------------------------------------------------------------------

resource "aws_security_group" "labs" {
  name        = "${local.name_prefix}-labs"
  description = "Lab Fargate tasks: only VPS can reach ttyd/gatekeeper"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-labs" }
}

resource "aws_vpc_security_group_ingress_rule" "labs_ttyd_from_vps" {
  security_group_id = aws_security_group.labs.id
  from_port         = 7681
  to_port           = 7681
  ip_protocol       = "tcp"
  cidr_ipv4         = "${var.vps_public_ip}/32"
  description       = "ttyd from VPS Traefik only"
}

resource "aws_vpc_security_group_ingress_rule" "labs_gatekeeper_from_vps" {
  security_group_id = aws_security_group.labs.id
  from_port         = 9999
  to_port           = 9999
  ip_protocol       = "tcp"
  cidr_ipv4         = "${var.vps_public_ip}/32"
  description       = "Gatekeeper validation from VPS backend only"
}

# Egress: ZERO Internet. A lab gets root, so the boundary must be the AWS
# network layer, not the container. The only legitimate outbound traffic is
# image pull (ECR) + log push (CloudWatch) at task start — both routed through
# private VPC endpoints below, never the Internet Gateway. Result: a lab cannot
# initiate any connection to the outside world (no crypto mining, no outbound
# attacks, no C2/exfil over TCP). Ingress (ttyd/gatekeeper from the VPS) still
# works because security groups are stateful — responses to VPS-initiated
# connections are allowed regardless of these egress rules.
#
# Residual (accepted): low-bandwidth DNS tunneling via the VPC resolver. Killing
# it would require Route 53 Resolver DNS Firewall (paid).

# ECR API + CloudWatch Logs, via the interface endpoints (private DNS).
resource "aws_vpc_security_group_egress_rule" "labs_to_vpce" {
  security_group_id            = aws_security_group.labs.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.vpce.id
  description                  = "HTTPS to interface endpoints (ECR API/DKR, CloudWatch Logs)"
}

# ECR image layers are served from S3 — reached via the S3 gateway endpoint,
# whose route is expressed as a managed prefix list.
resource "aws_vpc_security_group_egress_rule" "labs_to_s3" {
  security_group_id = aws_security_group.labs.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
  description       = "HTTPS to S3 gateway endpoint (ECR layer blobs)"
}

# DNS to the in-VPC Amazon resolver only (needed to resolve endpoint private
# DNS names). NOT 0.0.0.0/0 — the lab cannot reach external DNS servers.
resource "aws_vpc_security_group_egress_rule" "labs_dns_udp" {
  security_group_id = aws_security_group.labs.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = aws_vpc.main.cidr_block
  description       = "DNS (VPC resolver only)"
}

resource "aws_vpc_security_group_egress_rule" "labs_dns_tcp" {
  security_group_id = aws_security_group.labs.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = aws_vpc.main.cidr_block
  description       = "DNS TCP (VPC resolver only)"
}

# ---------------------------------------------------------------------------
# VPC endpoints: let lab tasks pull from ECR + ship logs WITHOUT Internet.
# Interface endpoints are AZ-scoped and billed per-AZ, so we place them only in
# public[0] — the single subnet where labs actually launch (ECS_SUBNET_ID /
# packer/EC2 all use subnet[0]). The S3 gateway endpoint is free.
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpce" {
  name        = "${local.name_prefix}-vpce"
  description = "Interface VPC endpoints: accept HTTPS from lab tasks only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-vpce" }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https_from_labs" {
  security_group_id            = aws_security_group.vpce.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.labs.id
  description                  = "HTTPS from lab tasks"
}

locals {
  # Minimum set for a private Fargate image pull + awslogs driver.
  interface_endpoint_services = toset(["ecr.api", "ecr.dkr", "logs"])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.public[0].id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "${local.name_prefix}-vpce-${each.value}" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = { Name = "${local.name_prefix}-vpce-s3" }
}

# ---------------------------------------------------------------------------
# ECR repo for lab images
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "labs" {
  name                 = "hardenthis/labs"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "labs" {
  repository = aws_ecr_repository.labs.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images per tag prefix"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 50
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# CloudWatch log group for lab containers
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "labs" {
  name              = "/ecs/${local.name_prefix}-labs"
  retention_in_days = 7
}

# ---------------------------------------------------------------------------
# IAM: execution role (ECR pull + CloudWatch logs)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lab_execution" {
  name               = "${local.name_prefix}-lab-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "lab_execution_managed" {
  role       = aws_iam_role.lab_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------------------------------------------------------------------------
# IAM: lab task role (ZERO PERMISSIONS)
# The container running inside the lab has access to nothing in the AWS account.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lab_task" {
  name               = "${local.name_prefix}-lab-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  # No policies attached — by design.
}

# ---------------------------------------------------------------------------
# IAM: lab EC2 instance role + instance profile (ZERO PERMISSIONS)
# Used by EC2-based labs (ones that need systemctl, iptables, etc.).
# Like lab_task: no policy attached, the lab VM has zero AWS access.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lab_ec2" {
  name               = "${local.name_prefix}-lab-ec2"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "lab_ec2" {
  name = "${local.name_prefix}-lab-ec2"
  role = aws_iam_role.lab_ec2.name
}

# ---------------------------------------------------------------------------
# ECS cluster (Fargate)
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "labs" {
  name = "${local.name_prefix}-labs-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # save money
  }
}

resource "aws_ecs_cluster_capacity_providers" "labs" {
  cluster_name       = aws_ecs_cluster.labs.name
  capacity_providers = ["FARGATE"]
}

# ---------------------------------------------------------------------------
# IAM user for the backend (running on VPS) to call ECS API
# ---------------------------------------------------------------------------

resource "aws_iam_user" "backend" {
  name = "${local.name_prefix}-backend-vps"
}

data "aws_iam_policy_document" "backend" {
  statement {
    sid    = "ECSManageLabs"
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "ecs:StopTask",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:TagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EC2DescribeENIForPublicIp"
    effect    = "Allow"
    actions   = ["ec2:DescribeNetworkInterfaces"]
    resources = ["*"]
  }

  statement {
    sid       = "PassRoleToECSTasks"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.lab_execution.arn, aws_iam_role.lab_task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # --- EC2 lab runtime: launch / terminate / describe / tag ---
  # Resources CREATED during RunInstances (must carry the ManagedBy=hardenthis tag)
  statement {
    sid     = "EC2RunInstancesTagged"
    effect  = "Allow"
    actions = ["ec2:RunInstances"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/ManagedBy"
      values   = ["hardenthis"]
    }
  }

  # Pre-existing resources referenced during RunInstances
  statement {
    sid     = "EC2RunInstancesExisting"
    effect  = "Allow"
    actions = ["ec2:RunInstances"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/*",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:subnet/*",
      "arn:aws:ec2:${var.aws_region}::image/*",
    ]
  }

  statement {
    sid     = "EC2CreateTags"
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:network-interface/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances"]
    }
  }

  statement {
    sid    = "EC2TerminateAndDescribeTagged"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:StopInstances",
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
    actions   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"]
    resources = ["*"]
  }

  statement {
    sid       = "PassRoleToEC2Labs"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.lab_ec2.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "CloudWatchLogsForLabs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups"]
    resources = ["${aws_cloudwatch_log_group.labs.arn}:*"]
  }

  statement {
    sid    = "S3UploadsBucket"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.s3_assets_bucket}",
      "arn:aws:s3:::${var.s3_assets_bucket}/*",
    ]
  }
}

resource "aws_iam_policy" "backend" {
  name        = "${local.name_prefix}-backend-permissions"
  description = "Permissions for the backend running on the VPS to manage labs"
  policy      = data.aws_iam_policy_document.backend.json
}

resource "aws_iam_user_policy_attachment" "backend" {
  user       = aws_iam_user.backend.name
  policy_arn = aws_iam_policy.backend.arn
}

# Access key for the backend user — output as sensitive
resource "aws_iam_access_key" "backend" {
  user = aws_iam_user.backend.name
}

# ---------------------------------------------------------------------------
# IAM user for the labs CI/CD pipeline (GitLab) to push lab images to ECR
# Separate from the backend user (least-privilege) — only ECR push perms.
# Add Packer/EC2 AMI build perms here later when you start building EC2 labs.
# ---------------------------------------------------------------------------

resource "aws_iam_user" "labs_ci" {
  name = "${local.name_prefix}-labs-ci"
}

data "aws_iam_policy_document" "labs_ci" {
  # --- ECR push for Docker-based labs ---
  statement {
    sid       = "ECRGetAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPullLabsRepo"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:CreateRepository",
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:TagResource",
    ]
    resources = [aws_ecr_repository.labs.arn]
  }

  # --- Packer perms: build AMI for EC2-runtime labs ---
  # Resources scoped to "*" because Packer creates ephemeral resources on the fly
  # (temp instance, snapshot, AMI) — AWS doesn't let us scope these by ARN.
  # Mitigation: this user has NO ECS perms, NO S3 perms, NO IAM write perms.
  statement {
    sid    = "PackerEC2"
    effect = "Allow"
    actions = [
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CopyImage",
      "ec2:CreateImage",
      "ec2:CreateKeypair",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteKeyPair",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSnapshot",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DescribeImageAttribute",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeRegions",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSnapshots",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVpcs",
      "ec2:DetachVolume",
      "ec2:GetPasswordData",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:RegisterImage",
      "ec2:RunInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }

  # PassRole so Packer can attach the builder instance profile to the temp EC2
  statement {
    sid       = "PassRoleToPackerBuilder"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.packer_builder.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # GetInstanceProfile so Packer can validate the profile exists before launching
  statement {
    sid       = "GetPackerInstanceProfile"
    effect    = "Allow"
    actions   = ["iam:GetInstanceProfile"]
    resources = [aws_iam_instance_profile.packer_builder.arn]
  }
}

resource "aws_iam_user_policy" "labs_ci" {
  name   = "labs-ci-permissions"
  user   = aws_iam_user.labs_ci.name
  policy = data.aws_iam_policy_document.labs_ci.json
}

resource "aws_iam_access_key" "labs_ci" {
  user = aws_iam_user.labs_ci.name
}

# ---------------------------------------------------------------------------
# S3 bucket for user-uploaded assets (avatars, course covers, etc.)
# Public-read on objects so the frontend can serve them via CDN_URL directly.
# Server-side encryption (AES256) enabled. Versioning OFF (assets are stable).
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "assets" {
  bucket = var.s3_assets_bucket
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false # we set a public-read bucket policy below
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "assets_public_read" {
  statement {
    sid       = "PublicReadObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket     = aws_s3_bucket.assets.id
  policy     = data.aws_iam_policy_document.assets_public_read.json
  depends_on = [aws_s3_bucket_public_access_block.assets]
}

resource "aws_s3_bucket_cors_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  cors_rule {
    allowed_methods = ["GET", "HEAD", "PUT"]
    allowed_origins = ["https://${var.domain_name}", "https://www.${var.domain_name}"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# ---------------------------------------------------------------------------
# Packer builder IAM (used to build EC2 lab AMIs from CI)
# - role + instance profile attached to the temporary Packer EC2 builder
# - SSM managed policy so Packer can use SSH-less provisioning (optional)
# Default Packer flow uses SSH, but having SSM available is a nice fallback.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "packer_builder" {
  name               = "${local.name_prefix}-packer-builder"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "packer_builder_ssm" {
  role       = aws_iam_role.packer_builder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "packer_builder" {
  name = "${local.name_prefix}-packer-builder"
  role = aws_iam_role.packer_builder.name
}
