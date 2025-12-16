################################################################################
# File: terraform/redis.tf
################################################################################

module "redis" {
  count        = var.redis_type == "redis" ? 1 : 0
  source       = "./modules/ecs-service"
  project_name = var.project_name
  environment  = var.environment
  container_config = [
    {
      docker_repository_name = var.redis_image.image
      image_tag              = var.redis_image.tag
      container_name         = "redis"
      container_port         = 6379
      container_port_name    = "redis-port"
      app_protocol           = null
      essential              = true

      health_check = {
        command      = ["CMD-SHELL", "redis-cli -h 127.0.0.1 ping | grep PONG || exit 1"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 10
      }
    }
  ]

  # Task Definition Configuration
  task_definition_config = {
    cpu    = var.redis_configuration.cpu
    memory = var.redis_configuration.memory 
  }

  # ECS Service Configuration
  ecs_service_config = {
    service_name                       = "redis"
    cluster_name                       = local.cluster_name
    desired_count                      = 1
    deployment_maximum_percent         = 200
    deployment_minimum_healthy_percent = 100
    health_check_grace_period_seconds  = 150
    enable_execute_command             = true
    capacity_provider                  = local.capacity_provider_name
    enable_blue_green                  = false  

    log_config = {
      enable_logging    = true
      retention_in_days = 7
    }

    service_connect_config = [
      {
      enabled        = true
      namespace      = local.namespace
      discovery_name = "redis"
      port_name      = "redis-port"
      client_alias = {
        port     = 6379
        dns_name = "redis"
      }
    }
    ]

    service_autoscaling_config = {
      enable = false
    }

    vpc_id          = local.vpc_id
    service_subnets = local.private_subnet_ids
  }

  # Load Balancer Configuration
  load_balancer_config = {
    create_lb             = false
  }
  depends_on = [ aws_service_discovery_http_namespace.service_discovery_namespace ]
}