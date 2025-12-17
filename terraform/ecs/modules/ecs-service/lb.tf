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
  
  dynamic "access_logs" {
    for_each = var.load_balancer_config.enable_access_logs ? [1] : []
    content {
      bucket  = var.load_balancer_config.access_logs_bucket
      prefix  = var.load_balancer_config.access_logs_prefix != "" ? var.load_balancer_config.access_logs_prefix : null
      enabled = true
    }
  }
  
  tags = {
    Name = "${local.service_name}-${random_id.suffix.hex}-load-balancer"
  }
}

# ============================================================================
# PRODUCTION LISTENER
# ============================================================================

resource "aws_lb_listener" "prod" {
  count = local.create_lb ? 1 : 0

  load_balancer_arn = aws_lb.lb[0].arn
  port              = var.load_balancer_config.prod_listener.port
  protocol          = var.load_balancer_config.prod_listener.protocol

  # TLS/HTTPS Configuration
  certificate_arn = contains(["HTTPS", "TLS"], var.load_balancer_config.prod_listener.protocol) ? var.load_balancer_config.prod_listener.certificate_arn : null
  ssl_policy      = contains(["HTTPS", "TLS"], var.load_balancer_config.prod_listener.protocol) ? var.load_balancer_config.prod_listener.ssl_policy : null

  # Default action - ALB uses fixed-response, NLB forwards to first target group
  dynamic "default_action" {
    for_each = local.lb_type == "application" ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.lb_type == "network" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.blue_tg[var.load_balancer_config.routing_rules[0].name].arn
    }
  }

  tags = {
    Name        = "${local.service_name}-prod-listener"
    Environment = var.environment
    Type        = "production"
  }
}

# ============================================================================
# TEST LISTENER (for Blue/Green Deployment)
# ============================================================================

resource "aws_lb_listener" "test" {
  count = local.create_lb && local.enable_bg ? 1 : 0

  load_balancer_arn = aws_lb.lb[0].arn
  port              = var.load_balancer_config.test_listener.port
  protocol          = var.load_balancer_config.test_listener.protocol

  # TLS/HTTPS Configuration
  certificate_arn = contains(["HTTPS", "TLS"], var.load_balancer_config.test_listener.protocol) ? var.load_balancer_config.test_listener.certificate_arn : null
  ssl_policy      = contains(["HTTPS", "TLS"], var.load_balancer_config.test_listener.protocol) ? var.load_balancer_config.test_listener.ssl_policy : null

  # Default action - ALB uses fixed-response, NLB forwards to green target group
  dynamic "default_action" {
    for_each = local.lb_type == "application" ? [1] : []
    content {
      type = "fixed-response"
      fixed_response {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.lb_type == "network" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.green_tg[var.load_balancer_config.routing_rules[0].name].arn
    }
  }

  tags = {
    Name = "${local.service_name}-test-listener"
    Type = "test"
  }
}

# ============================================================================
# TARGET GROUPS AND ROUTING RULES (with Blue/Green support)
# ============================================================================

# Blue Target Groups for each routing rule
resource "aws_lb_target_group" "blue_tg" {
  for_each = local.create_lb ? {
    for rule in var.load_balancer_config.routing_rules : rule.name => rule
  } : {}

  name        = "${local.service_name}-${random_id.suffix.hex}-${each.key}-b"
  port        = each.value.container_port
  protocol    = local.lb_type == "network" ? "TCP" : "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = local.lb_type == "application" ? each.value.health_check_path : null
    port                = "traffic-port"
    protocol            = local.lb_type == "network" ? "TCP" : "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = local.lb_type == "network" ? 10 : 5
    interval            = 30
    matcher             = local.lb_type == "application" ? "200" : null
  }

  tags = {
    Name  = "${local.service_name}-${each.key}-tg-blue"
    Rule  = each.key
    Color = "blue"
  }
  lifecycle {
    ignore_changes = [action]
    create_before_destroy = true
  }
}

# Green Target Groups for each routing rule (for Blue/Green deployment)
resource "aws_lb_target_group" "green_tg" {
  for_each = local.create_lb && local.enable_bg ? {
    for rule in var.load_balancer_config.routing_rules : rule.name => rule
  } : {}

  name        = "${local.service_name}-${random_id.suffix.hex}-${each.key}-g"
  port        = each.value.container_port
  protocol    = local.lb_type == "network" ? "TCP" : "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = local.lb_type == "application" ? each.value.health_check_path : null
    port                = "traffic-port"
    protocol            = local.lb_type == "network" ? "TCP" : "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = local.lb_type == "network" ? 10 : 5
    interval            = 30
    matcher             = local.lb_type == "application" ? "200" : null
  }

  tags = {
    Name  = "${local.service_name}-${each.key}-tg-green"
    Rule  = each.key
    Color = "green"
  }
}

# ============================================================================
# PRODUCTION LISTENER RULES (Host-based routing)
# ============================================================================

resource "aws_lb_listener_rule" "prod_rules" {
  for_each = local.create_lb && local.lb_type == "application" ? {
    for rule in var.load_balancer_config.routing_rules : rule.name => rule
  } : {}

  listener_arn = aws_lb_listener.prod[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_tg[each.key].arn
  }

  # Host-based routing condition
  dynamic "condition" {
    for_each = each.value.host != null ? [1] : []
    content {
      host_header {
        values = [each.value.host]
      }
    }
  }

  condition {
    path_pattern {
        values = ["${each.value.path}/*"]
    }
  }
  dynamic "transform" {
    for_each = each.value.path != "" ? [1] : []
    content {
      type = "url-rewrite"
      url_rewrite_config {
        rewrite {
          regex = "^${each.value.path}/(.*)$"
          replace = "/$1"
        }
      }
    }
  }


  tags = {
    Name = "${local.service_name}-${each.key}-prod-rule"
    Rule = each.key
    Type = "production"
  }

  lifecycle {
    ignore_changes = [action]
  }
}

# ============================================================================
# TEST LISTENER RULES (for Blue/Green deployment)
# ============================================================================

resource "aws_lb_listener_rule" "test_rules" {
  for_each = local.create_lb && local.lb_type == "application" && local.enable_bg ? {
    for rule in var.load_balancer_config.routing_rules : rule.name => rule
  } : {}

  listener_arn = aws_lb_listener.test[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green_tg[each.key].arn
  }

  # Host-based routing condition
  dynamic "condition" {
    for_each = each.value.host != null ? [1] : []
    content {
      host_header {
        values = [each.value.host]
      }
    }
  }

  condition {
    path_pattern {
        values = ["${each.value.path}/*"]
    }
  }
  dynamic "transform" {
    for_each = each.value.path != "" ? [1] : []
    content {
      type = "url-rewrite"
      url_rewrite_config {
        rewrite {
          regex = "^${each.value.path}/(.*)$"
          replace = "/$1"
        }
      }
    }
  }

  tags = {
    Name = "${local.service_name}-${each.key}-test-rule"
    Rule = each.key
    Type = "test"
  }

  lifecycle {
    ignore_changes = [action]
  }
}