################################################################################
# File: terraform/variables.tf
################################################################################

#########################################################################
#                           PROJECT DETAILS                             #
#########################################################################

variable "project_name" {
  type        = string
  description = "Name of the Project"
  default     = "portkey"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g., dev, prod)"
  default     = "dev"
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources in"
  default     = "us-west-2"
}

variable "environment_variables_file_path" {
  type        = string
  description = "Provide the relative path for environment-variables.json"
}

variable "secrets_file_path" {
  type        = string
  description = "Provide the relative path for secrets.json"
}

#########################################################################
#                         NETWORK CONFIGURATION                         #
#########################################################################

variable "create_new_vpc" {
  description = "Set to true to create a new VPC. Set to false to use an existing one."
  type        = bool
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC to be created (required if 'create_new_vpc' is true)."
  type        = string
  default     = null

  validation {
    condition     = !var.create_new_vpc || (var.vpc_cidr != null && var.vpc_cidr != "")
    error_message = "You must specify 'vpc_cidr' when 'create_new_vpc' is set to true."
  }
}

variable "num_az" {
  description = "Number of Availability Zones to use. Recommended: at least 2 for high availability."
  type        = number
  default     = 2

  validation {
    condition     = var.num_az > 0
    error_message = "num_az must be greater than 0."
  }
}

variable "single_nat_gateway" {
  description = "When true, creates a single NAT Gateway shared across all private subnets (cost-effective, lower availability). Set to false to create one NAT Gateway per AZ (higher availability, higher cost)."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "The ID of the existing VPC where resources (e.g., ecs service) will be created."
  type        = string
  default     = null

  validation {
    condition     = var.create_new_vpc || (var.vpc_id != null && var.vpc_id != "")
    error_message = "You must either enable 'create_new_vpc' or provide an existing 'vpc_id'."
  }
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs. Required if 'create_new_vpc' is false."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_new_vpc || length(var.public_subnet_ids) > 0
    error_message = "You must provide public subnet IDs when 'create_new_vpc' is set to false."
  }
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs. Required if 'create_new_vpc' is false."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_new_vpc || length(var.private_subnet_ids) > 0
    error_message = "You must provide private subnet IDs when 'create_new_vpc' is set to false."
  }
}
###########################################################################
#                      CLUSTER AND CAPACITY PROVIDER                      #
###########################################################################
variable "create_cluster" {
  description = "Set to true to create a new ECS cluster. Set to false to use an existing one."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the cluster where portkey services will be deployed. Must be provided if create_cluster = false"
  type        = string
  default     = null

  validation {
    condition     = var.create_cluster || (var.cluster_name != null && var.cluster_name != "")
    error_message = "You must either enable 'create_cluster' or provide an existing 'cluster_name'."
  }
}

variable "capacity_provider_name" {
  description = "Name of the cluster capacity provider. Must be provided if create_cluster = false"
  type        = string
  default     = null

  validation {
    condition     = var.create_cluster || (var.capacity_provider_name != null && var.capacity_provider_name != "")
    error_message = "You must either enable 'create_cluster' or provide an existing 'cluster_name'."
  }
}

variable "instance_type" {
  description = "EC2 instance type to associate with autoscaling group."
  type        = string
  default     = "t4g.medium"
}

variable "max_asg_size" {
  description = "Maximum number of EC2 in auto scaling group"
  type        = number
  default     = 3
}

variable "min_asg_size" {
  description = "Minimum number of EC2 in auto scaling group"
  type        = number
  default     = 1
}

variable "desired_asg_size" {
  description = "Desired number of EC2 in auto scaling group"
  type        = number
  default     = 2
}

variable "target_capacity" {
  description = "Desired percentage of cluster resources that ECS aims to maintain."
  type        = number
  default     = 100
}

###########################################################################
#                         DOCKER IMAGE CONFIGURATION                      #
###########################################################################
variable "gateway_image" {
  description = "Container image to use for the gateway."
  type = object({
    image = optional(string)
    tag   = optional(string)
  })
  default = {
    image = "portkeyai/gateway_enterprise"
    tag   = "latest"
  }
}

variable "data_service_image" {
  description = "Container image to use for the data service."
  type = object({
    image = optional(string)
    tag   = optional(string)
  })
  default = {
    image = "portkeyai/data-service"
    tag   = "latest"
  }
}

variable "docker_cred_secret_arn" {
  description = "ARN of AWS Secrets Manager's secret where docker credentials shared by Portkey is stored."
  type        = string
}

variable "redis_image" {
  description = "Container image to use for the data service."
  type = object({
    image = optional(string)
    tag   = optional(string)
  })
  default = {
    image = "redis"
    tag   = "7.2-alpine"
  }
}

###########################################################################
#                     GATEWAY SERVICE CONFIGURATION                       #
###########################################################################

variable "gateway_config" {
  description = "Gateway service configuration"
  type = object({
    desired_task_count = number
    cpu                = number
    memory             = number
    gateway_port       = number
    mcp_port           = number
  })
  default = {
    desired_task_count = 1
    cpu                = 256
    memory             = 1024
    gateway_port       = 8787
    mcp_port           = 8788
  }
}

variable "gateway_autoscaling" {
  description = "Gateway service autoscaling configuration"
  type = object({
    enable_autoscaling        = bool
    autoscaling_min_capacity  = number
    autoscaling_max_capacity  = number
    target_cpu_utilization    = number
    target_memory_utilization = number
    scale_in_cooldown         = number
    scale_out_cooldown        = number
  })
  default = {
    enable_autoscaling        = false
    autoscaling_min_capacity  = 1
    autoscaling_max_capacity  = 3
    target_cpu_utilization    = 70
    target_memory_utilization = 70
    scale_in_cooldown         = 120
    scale_out_cooldown        = 60
  }
}

variable "enable_blue_green" {
  description = "Define whether to configure blue-green deployment for gateway with load balancer"
  type        = bool
  default     = false
  validation {
    condition     = !(var.enable_blue_green && !var.create_lb)
    error_message = "Must set create_lb to true for enabling blue green deployment."
  }
}

variable "gateway_lifecycle_hook" {
  description = "Lifecycle hook configuration for gateway service"
  type = object({
    enable_lifecycle_hook = bool
    lifecycle_hook_stages = list(string)
  })
  default = {
    enable_lifecycle_hook = false
    lifecycle_hook_stages = []
  }
}

###########################################################################
#                       DATA SERVICE CONFIGURATION                        #
###########################################################################

variable "dataservice_config" {
  description = "Data service configuration"
  type = object({
    enable_dataservice = bool
    desired_task_count = number
    cpu                = number
    memory             = number
  })
  default = {
    enable_dataservice = false
    desired_task_count = 1
    cpu                = 256
    memory             = 1024
  }
}

variable "dataservice_autoscaling" {
  description = "Data service autoscaling configuration"
  type = object({
    enable_autoscaling        = bool
    autoscaling_min_capacity  = number
    autoscaling_max_capacity  = number
    target_cpu_utilization    = number
    target_memory_utilization = number
    scale_in_cooldown         = number
    scale_out_cooldown        = number
  })
  default = {
    enable_autoscaling        = false
    autoscaling_min_capacity  = 1
    autoscaling_max_capacity  = 3
    target_cpu_utilization    = 70
    target_memory_utilization = 70
    scale_in_cooldown         = 120
    scale_out_cooldown        = 60
  }
}

###########################################################################
#                            REDIS CONFIGURATION                          #
###########################################################################

variable "redis_configuration" {
  description = "Redis configuration object"
  type = object({
    redis_type = string
    cpu        = number
    memory     = number
    endpoint   = string
    tls        = bool
    mode       = string
  })
  default = {
    redis_type = "redis"
    cpu        = 256
    memory     = 512
    endpoint   = ""
    tls        = false
    mode       = "standalone"
  }
}

variable "redis_type" {
  description = "Specify Redis type."
  type        = string
  default     = "redis"
  validation {
    condition     = contains(["redis", "aws-elastic-cache"], var.redis_type)
    error_message = "'redis_type' must be one of: 'redis', 'aws-elastic-cache'."
  }
}

variable "redis_endpoint" {
  description = "Specify Redis endpoint."
  type        = string
  default     = ""
  validation {
    condition = (
      var.redis_type != "aws-elastic-cache" ||
      (
      var.redis_type == "aws-elastic-cache" && var.redis_endpoint != "")
    )
    error_message = "A valid AWS ElastiCache endpoint must be provided if 'type' = 'aws-elastic-cache'."
  }
}

variable "redis_cpu" {
  description = "Specify Redis CPU."
  type        = number
  default     = 256
  validation {
    condition = (
      var.redis_type != "redis" ||
      (
        var.redis_type == "redis" && var.redis_cpu > 0
    ))
    error_message = "A valid Redis CPU > 0 must be provided if 'type' = 'redis'."
  }
}
variable "redis_memory" {
  description = "Specify Redis memory."
  type        = number
  default     = 512
  validation {
    condition = (
      var.redis_type != "redis" ||
      (
        var.redis_type == "redis" && var.redis_memory > 0
    ))
    error_message = "A valid Redis memory > 0 must be provided if 'type' = 'redis'."
  }
}

variable "redis_tls_enabled" {
  description = "Specify whether Redis TLS is enabled on AWS ElastiCache."
  type        = bool
  default     = false
}

variable "redis_mode" {
  description = "Specify if cluster mode is enabled on AWS ElastiCache."
  type        = string
  default     = "standalone"
  validation {
    condition     = contains(["standalone", "cluster"], var.redis_mode)
    error_message = "'redis_mode' must be one of: 'standalone', 'cluster'."
  }
}



###########################################################################
#                           LOG STORE CONFIGURATION                       #
###########################################################################
variable "object_storage" {
  description = "Specify log stores."
  type = object({
    log_store_bucket   = string
    log_exports_bucket = optional(string, "")
    finetune_bucket    = optional(string, "")
    bucket_region      = string
  })
}

###########################################################################
#                           BEDROCK CONFIGURATION                       #
###########################################################################

variable "enable_bedrock_access" {
  description = "Enable access to bedrock"
  type        = bool
  default     = false
}

###########################################################################
#                       LOAD BALANCER CONFIGURATION                       #
###########################################################################

variable "create_lb" {
  description = "Create internal load balancer?"
  type        = bool
  default     = false
}

variable "internal_lb" {
  description = "Create internal load balancer or internet-facing."
  type        = bool
  default     = true
}

variable "lb_type" {
  description = "Specify load balancer type."
  type        = string
  default     = "network"
  validation {
    condition     = contains(["application", "network"], var.lb_type)
    error_message = "'lb_type' must be one of: 'application', 'network'."
  }
  validation {
    condition     = var.server_mode != "all" || var.lb_type == "application"
    error_message = "When server_mode is 'all', lb_type must be 'application' to support host-based routing for multiple services."
  }
}

variable "allowed_lb_cidrs" {
  description = "Provide IP ranges to whitelist in LB security group. Default 0.0.0.0/0 for internet-facing LB and VPC_CIDR for internal LB."
  type        = list(string)
  default     = []
}

variable "tls_certificate_arn" {
  description = "ACM certificate ARN to enable TLS-based listeners."
  type        = string
  default     = ""
}

variable "enable_lb_access_logs" {
  description = "Enable access logs for the Load Balancer. Requires lb_access_logs_bucket to be set."
  type        = bool
  default     = false
}

variable "lb_access_logs_bucket" {
  description = "S3 bucket name for storing Load Balancer access logs. Required if enable_lb_access_logs is true."
  type        = string
  default     = ""
  validation {
    condition     = !var.enable_lb_access_logs || (var.lb_access_logs_bucket != null && var.lb_access_logs_bucket != "")
    error_message = "lb_access_logs_bucket must be provided when enable_lb_access_logs is set to true."
  }
}

variable "lb_access_logs_prefix" {
  description = "S3 bucket prefix for Load Balancer access logs (optional)."
  type        = string
  default     = ""
}
###########################################################################
#                         ROUTING CONFIGURATION                           #
###########################################################################

variable "server_mode" {
  description = "Specify server mode for gateway"
  type        = string
  default     = "gateway"
  validation {
    condition     = contains(["gateway", "mcp", "all"], var.server_mode)
    error_message = "'server_mode' must be one of: 'gateway', 'mcp', 'all'."
  }
}
variable "alb_routing_configuration" {
  description = "ALB routing configuration"
  type = object({
    enable_path_based_routing = optional(bool, false)
    enable_host_based_routing = optional(bool, false)
    mcp_path                  = optional(string, "/mcp")
    gateway_path              = optional(string, "/gateway") 
    mcp_host                  = optional(string, "")
    gateway_host              = optional(string, "")
  })
}