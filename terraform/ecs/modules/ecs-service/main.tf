# ============================================================================
# FILE: modules/ecs-service/main.tf
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "random_id" "suffix" {
  byte_length = 6
}

# Extract existing namespace
data "aws_service_discovery_http_namespace" "service_namespace" {

  count = local.service_connect_enabled && local.service_namespace != null ? 1 : 0
  name  = local.service_namespace
}

locals {

  account_id = data.aws_caller_identity.current.account_id

  region = data.aws_region.current.region

  vpc_id = var.ecs_service_config.vpc_id

  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  task_role_arn = aws_iam_role.ecs_task_role.arn

  cluster_name = var.ecs_service_config.cluster_name

  cluster_arn = "arn:aws:ecs:${local.region}:${local.account_id}:cluster/${local.cluster_name}"

  service_name = var.ecs_service_config.service_name

  service_namespace = length(var.ecs_service_config.service_connect_config) > 0 ? var.ecs_service_config.service_connect_config[0].namespace : null

  service_connect_enabled = length(var.ecs_service_config.service_connect_config) > 0

  # Extract namespace arn
  namespace_arn = local.service_connect_enabled && local.service_namespace != null ? data.aws_service_discovery_http_namespace.service_namespace[0].arn : null

  enable_test_listener = var.ecs_service_config.deployment_configuration.enable_blue_green || var.ecs_service_config.deployment_configuration.linear_configuration != null || var.ecs_service_config.deployment_configuration.canary_configuration != null
  strategy             = var.ecs_service_config.deployment_configuration.enable_blue_green ? "BLUE_GREEN" : var.ecs_service_config.deployment_configuration.linear_configuration != null ? "LINEAR" : var.ecs_service_config.deployment_configuration.canary_configuration != null ? "CANARY" : "ROLLING"

  secret_arns = tolist(toset(flatten([
    for c in var.container_config : values(c.secrets)
  ])))

  all_secret_arns = concat(
    [
      for arn in local.secret_arns : "${arn}"
      ], [
      for c in var.container_config : try(c.docker_cred_secret_arn, null)
      if c.docker_cred_secret_arn != null && c.docker_cred_secret_arn != ""
  ])

  #
  # Extract all ARNs polcies to attach
  task_policy_map = var.task_definition_config.task_role_policy_arns_map

  # Extract load balancer configuration
  create_lb   = var.load_balancer_config.create_lb
  lb_type     = var.load_balancer_config.type
  lb_internal = var.load_balancer_config.lb_internal

  # Build container definition
  containers_definition = jsonencode([
    for container in var.container_config : {
      name = container.container_name
      image = container.ecr_repository_name != "" ? (
        "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com/${container.ecr_repository_name}:${container.image_tag}"
        ) : (
        "docker.io/${container.docker_repository_name}:${container.image_tag}"
      )
      essential = container.essential
      repositoryCredentials = (
        try(container.docker_cred_secret_arn, null) != null && try(container.docker_cred_secret_arn, "") != ""
        ) ? {
        credentialsParameter = container.docker_cred_secret_arn
      } : null
      # Port mappings - supports both single port (legacy) and multiple ports
      portMappings = length(container.container_ports) > 0 ? [
        for port in container.container_ports : {
          name          = port.container_port_name
          appProtocol   = port.app_protocol
          containerPort = port.container_port
          hostPort      = port.container_port
          protocol      = "tcp"
        }
        ] : container.container_port != null ? [
        {
          name          = container.container_port_name
          appProtocol   = container.app_protocol
          containerPort = container.container_port
          hostPort      = container.container_port
          protocol      = "tcp"
        }
      ] : []

      # Environment variables
      environment = [
        for key, value in container.environment_variables : {
          name  = key
          value = value
        }
      ]

      # Secrets
      secrets = [
        for key, value in container.secrets : {
          name      = key
          valueFrom = "${value}:${key}::"
        }
      ]

      healthCheck = {
        command     = container.health_check.command
        interval    = container.health_check.interval
        timeout     = container.health_check.timeout
        retries     = container.health_check.retries
        startPeriod = container.health_check.start_period
      }

      # Log configuration (conditionally include if defined)
      logConfiguration = var.ecs_service_config.log_config.enable_logging ? {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.project_name}/${local.service_name}"
          awslogs-region        = local.region
          awslogs-stream-prefix = "${local.service_name}-service"
        }
      } : null
    }
  ])

}
resource "aws_ecs_task_definition" "task_definition" {
  family                   = "${local.service_name}-${random_id.suffix.hex}"
  requires_compatibilities = ["EC2", "FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_definition_config.cpu
  memory                   = var.task_definition_config.memory
  execution_role_arn       = local.execution_role_arn
  task_role_arn            = local.task_role_arn
  track_latest             = var.task_definition_config.track_latest
  container_definitions    = local.containers_definition
}

resource "aws_ecs_service" "service" {
  name                               = local.service_name
  cluster                            = local.cluster_arn
  task_definition                    = aws_ecs_task_definition.task_definition.arn
  desired_count                      = var.ecs_service_config.desired_count
  enable_execute_command             = var.ecs_service_config.enable_execute_command
  force_new_deployment               = true
  deployment_maximum_percent         = var.ecs_service_config.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.ecs_service_config.deployment_minimum_healthy_percent
  health_check_grace_period_seconds  = local.create_lb ? var.ecs_service_config.health_check_grace_period_seconds : null

  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    strategy             = local.strategy
    bake_time_in_minutes = 1
    dynamic "lifecycle_hook" {
      for_each = var.ecs_service_config.lifecycle_hooks != null ? var.ecs_service_config.lifecycle_hooks : []
      content {
        hook_target_arn  = lifecycle_hook.value.hook_target_arn
        role_arn         = lifecycle_hook.value.role_arn
        lifecycle_stages = lifecycle_hook.value.lifecycle_stages
        hook_details     = lifecycle_hook.value.hook_details
      }
    }
    dynamic "linear_configuration" {
      for_each = local.strategy == "LINEAR" ? [1] : []
      content {
        step_bake_time_in_minutes = var.ecs_service_config.deployment_configuration.linear_configuration.step_bake_time_in_minutes
        step_percent              = var.ecs_service_config.deployment_configuration.linear_configuration.step_percent
      }
    }
    dynamic "canary_configuration" {
      for_each = local.strategy == "CANARY" ? [1] : []
      content {
        canary_bake_time_in_minutes = var.ecs_service_config.deployment_configuration.canary_configuration.canary_bake_time_in_minutes
        canary_percent              = var.ecs_service_config.deployment_configuration.canary_configuration.canary_percent
      }
    }
  }

  deployment_circuit_breaker {
    enable   = var.ecs_service_config.deployment_circuit_breaker.enable
    rollback = var.ecs_service_config.deployment_circuit_breaker.rollback
  }

  # Load balancer blocks for each routing rule (with Blue/Green support)
  dynamic "load_balancer" {
    for_each = local.create_lb ? {
      for rule in var.load_balancer_config.routing_rules : rule.name => rule
    } : {}
    content {
      target_group_arn = aws_lb_target_group.blue_tg[load_balancer.key].arn
      container_name   = var.load_balancer_config.container_name
      container_port   = load_balancer.value.container_port

      # Blue/Green deployment advanced configuration for ALB (uses listener rule ARNs)
      dynamic "advanced_configuration" {
        for_each = local.enable_test_listener && local.lb_type == "application" ? [1] : []
        content {
          alternate_target_group_arn = aws_lb_target_group.green_tg[load_balancer.key].arn
          production_listener_rule   = aws_lb_listener_rule.prod_rules[load_balancer.key].arn
          role_arn                   = aws_iam_role.ecs_load_balancer_role[0].arn
          test_listener_rule         = aws_lb_listener_rule.test_rules[load_balancer.key].arn
        }
      }

      # Blue/Green deployment advanced configuration for NLB (uses listener ARNs directly)
      dynamic "advanced_configuration" {
        for_each = local.enable_test_listener && local.lb_type == "network" ? [1] : []
        content {
          alternate_target_group_arn = aws_lb_target_group.green_tg[load_balancer.key].arn
          production_listener_rule   = aws_lb_listener.prod[0].arn
          role_arn                   = aws_iam_role.ecs_load_balancer_role[0].arn
          test_listener_rule         = aws_lb_listener.test[0].arn
        }
      }
    }
  }

  network_configuration {
    assign_public_ip = false
    subnets          = var.ecs_service_config.service_subnets
    security_groups  = [aws_security_group.service_sg.id]
  }

  dynamic "service_connect_configuration" {
    for_each = length(var.ecs_service_config.service_connect_config) > 0 ? [1] : []
    content {
      enabled   = true
      namespace = local.namespace_arn

      dynamic "service" {
        for_each = [for sc in var.ecs_service_config.service_connect_config : sc if sc.enabled]
        content {
          discovery_name = service.value.discovery_name
          port_name      = service.value.port_name

          dynamic "client_alias" {
            for_each = service.value.client_alias != null ? [service.value.client_alias] : []
            content {
              dns_name = client_alias.value.dns_name
              port     = client_alias.value.port
            }
          }
        }
      }
    }
  }

  capacity_provider_strategy {
    capacity_provider = var.ecs_service_config.capacity_provider
    weight            = 1
  }

  lifecycle {
    ignore_changes = [
      desired_count
    ]
  }

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"
  depends_on = [
    aws_iam_role_policy_attachment.ecs_execution_role_policy,
    aws_iam_role_policy_attachment.ecs_load_balancer_policy,
    aws_iam_role_policy_attachment.task_exec_policies,
    aws_iam_role_policy_attachment.task_role_policies,
    aws_iam_role_policy_attachment.task_role_policy_attach
  ]
}


# Create CloudWatch logging config
resource "aws_cloudwatch_log_group" "ecs_service" {
  count             = var.ecs_service_config.log_config.enable_logging ? 1 : 0
  name              = "/ecs/${var.project_name}/${local.service_name}"
  retention_in_days = var.ecs_service_config.log_config.retention_in_days
}