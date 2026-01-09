# ============================================================================
# FILE: modules/ecs-service/variables.tf
# ============================================================================

variable "project_name" {
  description = "Name of ECS cluster"
  type        = string
}

variable "environment" {
  description = "Name of environment"
  type        = string
}

# ============================================================================
# CONTAINERS CONFIGURATION
# ============================================================================

variable "container_config" {
  description = "List of container configurations including image, environment, and resources"
  type = list(object({
    # Image configuration
    ecr_repository_name    = optional(string, "")
    docker_repository_name = optional(string, "")
    docker_cred_secret_arn = optional(string, "")
    image_tag              = optional(string, "latest")
    container_name         = string

    # Single port configuration (legacy - use container_ports for multiple ports)
    container_port      = optional(number, null)
    container_port_name = optional(string, null)
    app_protocol        = optional(string, null)

    # Multiple ports configuration
    container_ports = optional(list(object({
      container_port      = number
      container_port_name = string
      app_protocol        = optional(string, null)
    })), [])

    # Environment variables and secrets
    environment_variables = optional(map(string), {})
    secrets               = optional(map(string), {})

    # Container configuration
    command     = optional(list(string))
    entry_point = optional(list(string))
    essential   = optional(bool, false)

    # Health check
    health_check = object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 60)
    })

  }))

  validation {
    condition = alltrue([
      for container in var.container_config :
      (container.docker_repository_name != null && container.docker_repository_name != "") ||
      (container.ecr_repository_name != null && container.ecr_repository_name != "")
    ])
    error_message = "Each container must have either 'docker_repository_name' or 'ecr_repository_name' provided (non-empty)."
  }



}


# ============================================================================
# TASK RESOURCES
# ============================================================================
variable "task_definition_config" {
  description = "Configuration for the ECS task definition"
  type = object({
    cpu                       = optional(string, "256")
    memory                    = optional(string, "1024")
    track_latest              = optional(bool, false)
    task_role_policy_arns_map = optional(map(string), {})
  })
  validation {
    condition = (
      var.task_definition_config.cpu == null ||
      contains(["256", "512", "1024", "2048", "4096", "8192", "16384"], var.task_definition_config.cpu)
    )
    error_message = "Invalid CPU value. Allowed values are 256, 512, 1024, 2048, 4096, 8192, or 16384 (in CPU units)."
  }

  validation {
    condition = (
      var.task_definition_config.memory == null ||
      contains(["512", "1024", "2048", "3072", "4096", "5120", "6144", "7168", "8192", "16384", "30720"], var.task_definition_config.memory)
    )
    error_message = "Invalid memory value. Allowed values depend on CPU size. Example valid values: 512, 1024, 2048, 4096, 8192, 16384, etc. For more details refer - https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html"
  }

}

# ============================================================================
# SERVICE CONFIGURATION
# ============================================================================

variable "ecs_service_config" {
  description = "Configuration for ECS service"
  type = object({
    service_name                       = string
    cluster_name                       = string
    desired_count                      = optional(number, 1)
    launch_type                        = optional(string, "FARGATE")
    platform_version                   = optional(string, "LATEST")
    deployment_maximum_percent         = optional(number, 200)
    deployment_minimum_healthy_percent = optional(number, 100)
    health_check_grace_period_seconds  = optional(number, 60)
    enable_execute_command             = optional(bool, true)

    capacity_provider = string


    # Deployment Strategy
    deployment_configuration = optional(object({
      enable_blue_green = optional(bool, false)
      canary_configuration = optional(object({
        canary_percent              = optional(number, 200) # Percentage of traffic to route to canary
        canary_bake_time_in_minutes = optional(number, 100) # Time to wait run canary deployment before full traffic shift to new version
      }), null)
      linear_configuration = optional(object({
        step_bake_time_in_minutes = optional(number, 100) # Time to wait after each step before the next step starts
        step_percent              = optional(number, 10)  # Percentage of traffic to shift per step (3-100%) 
      }), null)

    }), null)

    deployment_circuit_breaker = optional(object({
      enable   = optional(bool, true)
      rollback = optional(bool, true)
    }))

    lifecycle_hooks = optional(list(object({
      hook_target_arn  = string
      role_arn         = string
      lifecycle_stages = list(string)
      hook_details     = optional(string, null)
    })), [])
    log_config = object({
      enable_logging    = optional(bool, true)
      retention_in_days = optional(number, 14)
    })

    service_connect_config = optional(list(object({
      enabled        = bool
      namespace      = optional(string)
      discovery_name = optional(string)
      port_name      = optional(string)
      client_alias = optional(object({
        port     = number
        dns_name = string
      }))
    })), [])

    service_autoscaling_config = optional(object({
      enable                    = optional(bool, false)
      min_capacity              = optional(number, 1)
      max_capacity              = optional(number, 2)
      target_cpu_utilization    = optional(number, null)
      target_memory_utilization = optional(number, null)
      disable_scale_in          = optional(bool, false)
      suspended                 = optional(bool, false)
      scale_in_cooldown         = optional(number, 120)
      scale_out_cooldown        = optional(number, 60)
    }), {})

    # Network configuration
    vpc_id          = string
    service_subnets = list(string)
  })
}

# ============================================================================
# LOAD BALANCER
# ============================================================================

variable "load_balancer_config" {
  description = "Configuration for Application Load Balancer and target groups"
  type = object({
    # ALB Settings
    create_lb                        = optional(bool, false)
    lb_internal                      = optional(bool, false)
    lb_subnets                       = optional(list(string), []) # Must provide public subnet if creating internet-facing load balancer
    type                             = optional(string, "application")
    enable_deletion_protection       = optional(bool, false)
    enable_cross_zone_load_balancing = optional(bool, false)


    # Container to associate with load balancer
    container_name = optional(string, "app")


    # Production Listener Configuration
    prod_listener = optional(object({
      protocol        = optional(string, "HTTP") # ALB - HTTP or HTTPS / NLB - TCP or TLS
      port            = optional(number, 80)
      certificate_arn = optional(string, null) # Required if HTTPS or TLS
      ssl_policy      = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    }), null)

    # Test Listener Configuration (for Blue/Green)
    test_listener = optional(object({
      protocol        = optional(string, "HTTP")
      port            = optional(number, 8080)
      certificate_arn = optional(string, null) # Required only if HTTPS or TLS
      ssl_policy      = optional(string, "ELBSecurityPolicy-TLS13-1-2-2021-06")
    }), null)

    # Access Logs Configuration
    enable_access_logs = optional(bool, false)
    access_logs_bucket = optional(string, "")
    access_logs_prefix = optional(string, "")

    # Routing Rules (host-based for ALB, single rule for NLB)
    routing_rules = optional(list(object({
      name              = string                      # Unique name for the rule
      priority          = number                      # Priority of the rule (lower = higher priority)
      container_port    = number                      # Container port to forward traffic to
      health_check_path = optional(string, "/health") # Health check path for the target group
      host              = optional(string, null)      # Host headers for ALB (e.g., ["mcp.example.com"])
      path              = optional(string, "")        # Path pattern for ALB (e.g., "/mcp/*")
    })), [])
  })
  validation {
    condition = (
      var.load_balancer_config.type == null ||
      contains(["application", "network"], var.load_balancer_config.type)
    )
    error_message = "Load balancer type must be either 'application' or 'network'"
  }
  validation {
    condition = (
      !var.load_balancer_config.create_lb ||
      length(var.load_balancer_config.lb_subnets) > 0
    )
    error_message = "lb_subnets must be provided when create_lb is true"
  }

  validation {
    condition = (
      var.load_balancer_config.prod_listener == null ||
      (var.load_balancer_config.prod_listener.protocol != "HTTPS" || var.load_balancer_config.prod_listener.protocol != "TLS") ||
      var.load_balancer_config.prod_listener.certificate_arn != null
    )
    error_message = "certificate_arn is required in prod_listener when protocol is HTTPS or TLS"
  }

  validation {
    condition = (
      var.load_balancer_config.test_listener == null ||
      (var.load_balancer_config.test_listener.protocol != "TLS" || var.load_balancer_config.test_listener.protocol != "TLS") ||
      var.load_balancer_config.test_listener.certificate_arn != null
    )
    error_message = "certificate_arn is required in test_listener when protocol is HTTPS"
  }
}