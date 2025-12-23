################################################################################
# File: terraform/gateway.tf
################################################################################

module "gateway" {
  source       = "./modules/ecs-service"
  project_name = var.project_name
  environment  = var.environment
  container_config = [
    {
      docker_repository_name = var.gateway_image.image
      image_tag              = var.gateway_image.tag
      container_name         = "gateway"
      docker_cred_secret_arn = var.docker_cred_secret_arn
      essential              = true
      environment_variables = merge(
        local.gateway_variables,
        local.common_env,
        local.gateway_env
      )
      secrets = local.gateway_secrets

      # List of ports/protocols exposed by this container
      container_ports = [
        for port in [
          var.server_mode == "all" || var.server_mode == "gateway" ? {
            container_port      = var.gateway_config.gateway_port
            container_port_name = "gateway"
            app_protocol        = "http"
          } : null,
          var.server_mode == "all" || var.server_mode == "mcp" ? {
            container_port      = var.gateway_config.mcp_port
            container_port_name = "mcp"
            app_protocol        = "http"
          } : null
        ] : port if port != null
      ]

      health_check = {
        command      = ["CMD-SHELL", var.server_mode == "all" || var.server_mode == "gateway" ? "wget -qO- http://localhost:${var.gateway_config.gateway_port}/v1/health || exit 1" : "wget -qO- http://localhost:${var.gateway_config.mcp_port}/v1/health || exit 1"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 60
      }
    }
  ]

  # Task Definition Configuration
  task_definition_config = {
    cpu                       = var.gateway_config.cpu
    memory                    = var.gateway_config.memory
    task_role_policy_arns_map = local.gateway_task_role_policies
    track_latest              = true
  }


  # ECS Service Configuration
  ecs_service_config = {
    service_name                       = "gateway"
    cluster_name                       = local.cluster_name
    desired_count                      = var.gateway_config.desired_task_count
    deployment_maximum_percent         = 200
    deployment_minimum_healthy_percent = 100
    health_check_grace_period_seconds  = 150
    enable_execute_command             = true
    capacity_provider                  = local.capacity_provider_name
    enable_blue_green                  = var.enable_blue_green
    lifecycle_hooks = var.gateway_lifecycle_hook.enable_lifecycle_hook ? [
      {
        hook_target_arn  = aws_lambda_function.ecs_hook_lambda[0].arn
        role_arn         = aws_iam_role.ecs_hook_role[0].arn
        lifecycle_stages = var.gateway_lifecycle_hook.lifecycle_hook_stages
      }
    ] : null
    log_config = {
      enable_logging    = true
      retention_in_days = 14
    }

    service_connect_config = [
      for config in [
        var.server_mode == "all" || var.server_mode == "gateway" ? {
          enabled        = true
          namespace      = local.namespace
          discovery_name = "gateway"
          port_name      = "gateway"
          client_alias = {
            port     = var.gateway_config.gateway_port
            dns_name = "gateway"
          }
        } : null,
        var.server_mode == "all" || var.server_mode == "mcp" ? {
          enabled        = true
          namespace      = local.namespace
          discovery_name = "mcp"
          port_name      = "mcp"
          client_alias = {
            port     = var.gateway_config.mcp_port
            dns_name = "mcp"
          }
        } : null
      ] : config if config != null
    ]

    service_autoscaling_config = {
      enable                    = var.gateway_autoscaling.enable_autoscaling
      min_capacity              = var.gateway_autoscaling.autoscaling_min_capacity
      max_capacity              = var.gateway_autoscaling.autoscaling_max_capacity
      disable_scale_in          = false
      target_cpu_utilization    = var.gateway_autoscaling.target_cpu_utilization
      target_memory_utilization = var.gateway_autoscaling.target_memory_utilization
      scale_in_cooldown         = var.gateway_autoscaling.scale_in_cooldown
      scale_out_cooldown        = var.gateway_autoscaling.scale_out_cooldown
    }

    vpc_id          = local.vpc_id
    service_subnets = local.private_subnet_ids
  }

  # Load Balancer Configuration
  # Supports host-based routing with Application Load Balancer
  load_balancer_config = {
    create_lb          = var.create_lb
    lb_internal        = var.internal_lb
    type               = var.lb_type
    lb_subnets         = var.internal_lb ? local.private_subnet_ids : local.public_subnet_ids
    container_name     = "gateway"
    enable_access_logs = var.enable_lb_access_logs
    access_logs_bucket = var.enable_lb_access_logs ? var.lb_access_logs_bucket : ""
    access_logs_prefix = var.lb_access_logs_prefix

    prod_listener = {
      protocol        = var.lb_type == "application" ? (var.tls_certificate_arn != "" ? "HTTPS" : "HTTP") : (var.tls_certificate_arn != "" ? "TLS" : "TCP")
      port            = var.tls_certificate_arn != "" ? 443 : 80
      certificate_arn = var.tls_certificate_arn != "" ? var.tls_certificate_arn : null
    }
    test_listener = var.enable_blue_green ? {
      protocol        = var.lb_type == "application" ? (var.tls_certificate_arn != "" ? "HTTPS" : "HTTP") : (var.tls_certificate_arn != "" ? "TLS" : "TCP")
      port            = var.tls_certificate_arn != "" ? 8443 : 8080
      certificate_arn = var.tls_certificate_arn != "" ? var.tls_certificate_arn : null
    } : null
    routing_rules = local.routing_rules
  }
  depends_on = [
    aws_service_discovery_http_namespace.service_discovery_namespace,
    module.redis
  ]
}




