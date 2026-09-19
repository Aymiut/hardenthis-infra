# ---------------------------------------------------------------------------
# Backend — NestJS API
# ---------------------------------------------------------------------------

resource "aws_service_discovery_service" "backend" {
  name = "backend"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.name_prefix}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn            = var.backend_task_role_arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = var.backend_image
    essential = true

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [
      { name = "NODE_ENV", value = "production" },
      { name = "PORT", value = "3000" },
      { name = "FRONTEND_URL", value = var.frontend_url },
      { name = "COOKIE_SECURE", value = "true" },
      { name = "COOKIE_DOMAIN", value = ".${var.domain_name}" },
      { name = "DOMAIN_NAME", value = var.domain_name },
      { name = "INTERNAL_BACKEND_URL", value = "http://backend.${var.name_prefix}.internal:3000" },
      { name = "INTERNAL_FRONTEND_URL", value = "http://frontend.${var.name_prefix}.internal:3001" },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "ECS_CLUSTER_NAME", value = "${var.name_prefix}-cluster" },
      { name = "ECS_SUBNET_ID", value = var.labs_subnet_id },
      { name = "ECS_SECURITY_GROUP_ID", value = var.labs_sg_id_for_tasks },
      { name = "ECS_ASSIGN_PUBLIC_IP", value = "DISABLED" },
      { name = "ECS_TASK_ROLE_ARN", value = var.lab_task_role_arn },
      { name = "ECS_EXECUTION_ROLE_ARN", value = var.ecs_execution_role_arn },
      { name = "REDIS_URL", value = "rediss://default:${var.redis_auth_token}@${var.redis_endpoint}:6379" },
      { name = "ECR_REGISTRY", value = "${split("/", var.backend_image)[0]}" },
      { name = "JWT_ACCESS_EXPIRATION", value = "15m" },
      { name = "JWT_REFRESH_EXPIRATION", value = "7d" },
      { name = "LAB_MAX_DURATION_HOURS", value = "4" },
      { name = "MAX_ACTIVE_LABS_PER_USER", value = "1" },
      { name = "LOG_LEVEL", value = "info" },
      { name = "TERMINAL_SECRET", value = var.terminal_secret },
      { name = "LABS_LOG_GROUP", value = "/ecs/${var.name_prefix}-labs" },
      # EC2 lab config
      { name = "LAB_EC2_SUBNET_ID", value = var.labs_subnet_id },
      { name = "LAB_EC2_SECURITY_GROUP_ID", value = var.labs_sg_id_for_tasks },
      { name = "LAB_EC2_INSTANCE_PROFILE_ARN", value = var.lab_ec2_instance_profile_arn },
      { name = "LAB_EC2_INSTANCE_TYPE", value = var.lab_ec2_instance_type },
      # S3 assets (image uploads)
      { name = "S3_ASSETS_BUCKET", value = var.s3_assets_bucket },
      { name = "CDN_URL", value = var.cdn_url },
    ]

    secrets = [
      { name = "DATABASE_URL", valueFrom = var.database_url_secret_arn },
      { name = "JWT_ACCESS_SECRET", valueFrom = var.jwt_access_secret_arn },
      { name = "JWT_REFRESH_SECRET", valueFrom = var.jwt_refresh_secret_arn },
      { name = "ADMIN_SYNC_SECRET", valueFrom = var.admin_sync_secret_arn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = var.backend_log_group_name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "backend"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3000/ || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

resource "aws_ecs_service" "backend" {
  name            = "${var.name_prefix}-backend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.backend_sg_id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
  }
}
