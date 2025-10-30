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
      container_port         = 8787
      container_port_name    = "gateway-port"
      app_protocol           = "http"
      essential              = true
      environment_variables = merge(
        local.gateway_variables,
        local.common_env,
        local.gateway_env
      )
      secrets = local.gateway_secrets

      health_check = {
        command      = ["CMD-SHELL", "wget -qO- http://localhost:8787/v1/health || exit 1"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 60
      }
    }
  ]

  # Task Definition Configuration
  task_definition_config = {
    cpu    = var.gateway_config.cpu
    memory = var.gateway_config.memory
    task_role_policy_arns_map = local.gateway_task_role_policies
    track_latest = true                                                 # If set to true ECS automatically updates the service to use the latest task definition revision whenever a new one is registered.
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
    enable_blue_green                  = var.enable_blue_green # Define where to ena

    log_config = {
      enable_logging    = true
      retention_in_days = 14
    }

    service_connect_config = {
      enabled        = true
      namespace      = local.namespace
      discovery_name = "gateway"
      port_name      = "gateway-port"
      client_alias = {
        port     = 8787
        dns_name = "gateway"
      }
    }

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
  load_balancer_config = {
    create_lb         = var.create_nlb
    lb_internal       = var.internal_nlb
    type              = "network"
    lb_subnets        = var.internal_nlb ? local.private_subnet_ids : local.public_subnet_ids
    container_name    = "gateway"
    container_port    = 8787
    health_check_path = "/v1/health"
    prod_listener = {
      protocol = var.tls_certificate_arn != "" ? "TLS" : "TCP"
      port     = var.tls_certificate_arn != "" ? 443 : 80
    }
    test_listener = var.enable_blue_green ? {
      protocol = var.tls_certificate_arn != "" ? "TLS" : "TCP"
      port     = var.tls_certificate_arn != "" ? 8443 : 8080
    } : null
  }
  depends_on = [ 
    aws_service_discovery_http_namespace.service_discovery_namespace,
    module.redis 
  ]
}




