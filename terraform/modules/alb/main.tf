# modules/alb/main.tf
# Internet-facing ALB — central entry point.
# - Port 80  : redirect to HTTPS
# - Port 443 : TLS terminated here, forwarded as HTTP to Traefik EC2
#
# Traefik then routes based on Host header:
#   hardenthis.com       -> frontend ECS
#   api.hardenthis.com   -> backend ECS
#   <lab>.hardenthis.com -> lab ECS (dynamic, from Redis)
#
# DNS records (apex + wildcard -> ALB) are created on Cloudflare manually.

resource "aws_lb" "main" {
  name               = var.name_prefix
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }

  tags = {
    Name = var.name_prefix
  }
}

# ---------------------------------------------------------------------------
# S3 bucket for ALB access logs
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.name_prefix}-alb-logs"

  tags = {
    Name = "${var.name_prefix}-alb-logs"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::127311923021:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${var.aws_account_id}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${var.aws_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Target group — Traefik EC2 instance
# ---------------------------------------------------------------------------

resource "aws_lb_target_group" "traefik" {
  name        = "${var.name_prefix}-traefik"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/ping"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.name_prefix}-traefik"
  }
}

resource "aws_lb_target_group_attachment" "traefik" {
  target_group_arn = aws_lb_target_group.traefik.arn
  target_id        = var.traefik_instance_id
  port             = 80
}

# ---------------------------------------------------------------------------
# Listener: HTTP (80) — redirect to HTTPS
# ---------------------------------------------------------------------------

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ---------------------------------------------------------------------------
# Listener: HTTPS (443) — forward all traffic to Traefik
# ---------------------------------------------------------------------------

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik.arn
  }
}
