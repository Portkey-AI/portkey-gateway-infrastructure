################################################################################
# File: terraform/data-service.tf
################################################################################

module "data_service" {
  count        = var.dataservice_config.enable_dataservice ? 1 : 0
  source       = "./modules/ecs-service"
  project_name = var.project_name
  environment  = var.environment
  container_config = [
    {
      docker_repository_name = var.data_service_image.image
      image_tag              = var.data_service_image.tag
      container_name         = "data-service"
      docker_cred_secret_arn = var.docker_cred_secret_arn
      container_port         = 8081
      container_port_name    = "data-service-port"
      essential              = true
      environment_variables = merge(
        local.dataservice_variables,
        local.common_env,
        local.dataservice_env
      )
      secrets = local.dataservice_secrets

      health_check = {
        command      = ["CMD-SHELL", "wget -qO- http://localhost:8081/health || exit 1"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 60
      }
    }
  ]

  # Task Definition Configuration
  task_definition_config = {
    cpu    = var.dataservice_config.cpu
    memory = var.dataservice_config.memory
    task_role_policy_arns_map = local.data_service_task_role_policies
    track_latest = true 
  }

  # ECS Service Configuration
  ecs_service_config = {
    service_name                       = "data-service"
    cluster_name                       = local.cluster_name
    desired_count                      = var.dataservice_config.desired_task_count
    deployment_maximum_percent         = 200
    deployment_minimum_healthy_percent = 100
    health_check_grace_period_seconds  = 150
    enable_execute_command             = true
    capacity_provider                  = local.capacity_provider_name
    enable_blue_green                  = false

    log_config = {
      enable_logging    = true
      retention_in_days = 14
    }

    service_connect_config = [
      {
      enabled        = true
      namespace      = local.namespace
      discovery_name = "data-service"
      port_name      = "data-service-port"
      client_alias = {
        port     = 8081
        dns_name = "data-service"
      }
    }
    ]

    service_autoscaling_config = {
      enable                    = var.dataservice_autoscaling.enable_autoscaling
      min_capacity              = var.dataservice_autoscaling.autoscaling_min_capacity
      max_capacity              = var.dataservice_autoscaling.autoscaling_max_capacity
      disable_scale_in          = false
      target_cpu_utilization    = var.dataservice_autoscaling.target_cpu_utilization
      target_memory_utilization = var.dataservice_autoscaling.target_memory_utilization
      scale_in_cooldown         = var.dataservice_autoscaling.scale_in_cooldown
      scale_out_cooldown        = var.dataservice_autoscaling.scale_out_cooldown
    }

    vpc_id          = local.vpc_id
    service_subnets = local.private_subnet_ids
  }

  # Load Balancer Configuration
  load_balancer_config = {
    create_lb = false
  }
  depends_on = [ 
    aws_service_discovery_http_namespace.service_discovery_namespace,
    module.redis 
  ]
}


