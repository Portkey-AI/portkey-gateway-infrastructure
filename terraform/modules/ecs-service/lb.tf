# ============================================================================
# FILE: modules/ecs-service/lb.tf
# ============================================================================

# Create Load Balancer
resource "aws_lb" "lb" {
  count                            = local.create_lb ? 1 : 0
  name                             = "${local.service_name}-${random_id.suffix.hex}-lb"
  internal                         = local.lb_internal
  load_balancer_type               = local.lb_type
  enable_deletion_protection       = var.load_balancer_config.enable_deletion_protection
  enable_cross_zone_load_balancing = var.load_balancer_config.enable_cross_zone_load_balancing
  security_groups                  = [aws_security_group.lb_sg[0].id]
  subnets                          = var.load_balancer_config.lb_subnets
  drop_invalid_header_fields       = local.lb_type == "application" ? true : null
  tags = {
    Name = "${local.service_name}-${random_id.suffix.hex}-load-balancer-${random_id.suffix.hex}"
  }
}

# Create Target Group - Blue
resource "aws_lb_target_group" "blue_tg" {
  count       = local.create_lb ? 1 : 0
  name        = "${local.service_name}-${random_id.suffix.hex}-blue-tg"
  port        = var.load_balancer_config.container_port
  protocol    = local.lb_type == "network" ? "TCP" : "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = var.load_balancer_config.health_check_path
    port                = "traffic-port"
    protocol            = var.load_balancer_config.health_check_protocol
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = var.load_balancer_config.health_check_matcher
  }
  tags = {
    Name  = "${local.service_name}-${random_id.suffix.hex}-blue-tg"
    Color = "blue"
  }
}

# Create Target Group - Green
resource "aws_lb_target_group" "green_tg" {
  count       = local.create_lb && local.enable_bg ? 1 : 0
  name        = "${local.service_name}-${random_id.suffix.hex}-green-tg"
  port        = var.load_balancer_config.container_port
  protocol    = local.lb_type == "network" ? "TCP" : "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = var.load_balancer_config.health_check_path
    port                = "traffic-port"
    protocol            = var.load_balancer_config.health_check_protocol
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = var.load_balancer_config.health_check_matcher
  }
  tags = {
    Name  = "${local.service_name}-${random_id.suffix.hex}-green-tg"
    Color = "green"
  }
}

# Production Listener
resource "aws_lb_listener" "prod" {
  count = local.create_lb ? 1 : 0

  load_balancer_arn = aws_lb.lb[0].arn
  port              = var.load_balancer_config.prod_listener.port
  protocol          = var.load_balancer_config.prod_listener.protocol

  # TLS/HTTPS Configuration
  certificate_arn = var.load_balancer_config.prod_listener.protocol == "HTTPS" || var.load_balancer_config.prod_listener.protocol == "TLS" ? var.load_balancer_config.prod_listener.certificate_arn : null
  ssl_policy      = var.load_balancer_config.prod_listener.protocol == "HTTPS" || var.load_balancer_config.prod_listener.protocol == "TLS" ? var.load_balancer_config.prod_listener.ssl_policy : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_tg[0].arn
  }

  tags = {
    Name        = "${local.service_name}-prod-listener"
    Environment = var.environment
    Type        = "main"
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# Production Listener Rule (Required for ECS Blue/Green with advanced_configuration)
resource "aws_lb_listener_rule" "prod_rule" {
  count = local.create_lb && local.lb_type == "application" && local.enable_bg ? 1 : 0

  listener_arn = aws_lb_listener.prod[0].arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_tg[0].arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

# Test Listener (for Blue/Green)
resource "aws_lb_listener" "test" {
  count = local.create_lb && local.enable_bg ? 1 : 0

  load_balancer_arn = aws_lb.lb[0].arn
  port              = var.load_balancer_config.test_listener.port
  protocol          = var.load_balancer_config.test_listener.protocol

  # TLS/HTTPS Configuration
  certificate_arn = var.load_balancer_config.test_listener.protocol == "HTTPS" || var.load_balancer_config.test_listener.protocol == "TLS" ? var.load_balancer_config.test_listener.certificate_arn : null
  ssl_policy      = var.load_balancer_config.test_listener.protocol == "HTTPS" || var.load_balancer_config.test_listener.protocol == "TLS" ? var.load_balancer_config.test_listener.ssl_policy : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_tg[0].arn
  }

  tags = {
    Name = "${local.service_name}-test-listener"
    Type = "test"
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# Test Listener Rule (Optional)
resource "aws_lb_listener_rule" "test_rule" {

  count = local.create_lb && local.lb_type == "application" && local.enable_bg ? 1 : 0

  listener_arn = aws_lb_listener.test[0].arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_tg[0].arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}