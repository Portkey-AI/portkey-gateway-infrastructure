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
  default     = 70
}

###########################################################################
#                             IMAGE CONFIGURATION                         #
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
variable "gateway_desired_task" {
  description = "Configure desired number of Gateway Service Tasks to run."
  type = number
  default = 1
}

variable "gateway_cpu" {
  description = "Configure cpu for Gateway Service Tasks."
  type = number
  default = 256
}

variable "gateway_memory" {
  description = "Configure memory for Gateway Service Tasks."
  type = number
  default = 1024
}

variable "gateway_enable_autoscaling" {
  description = "Specify whether to enable autosclaing on Gateway tasks."
  type = bool
  default = false
}

variable "gateway_min_capacity" {
  description = "Specify minimum number of task to run in Gateway Service."
  type = number
  default = 1
}

variable "gateway_max_capacity" {
  description = "Specify maximum number of task to run in Gateway Service."
  type = number
  default = 3
}

variable "gateway_target_cpu_utilization" {
  description = "Specify target cpu utilization % that ECS autoscaling should try to maintain for Gateway tasks."
  type = number
  default = null
  validation {
    condition = (
      var.gateway_target_cpu_utilization == null || 
      (var.gateway_target_cpu_utilization <= 100 && var.gateway_target_cpu_utilization > 0)
    )
    error_message = "'gateway_target_cpu_utilization' must be between 0-100."
  }
  validation {
    condition = (
      !var.gateway_enable_autoscaling || 
      var.gateway_target_cpu_utilization != null || 
      var.gateway_target_memory_utilization != null
    )
    error_message = "When 'gateway_enable_autoscaling' is true, at least one of 'gateway_target_cpu_utilization' or 'gateway_target_memory_utilization' must be set."
  }
}

variable "gateway_target_memory_utilization" {
  description = "Specify target memory utilization % that ECS autoscaling should try to maintain for Gateway tasks."
  type = number
  default = null
  validation {
    condition = (
      var.gateway_target_memory_utilization == null || 
      (var.gateway_target_memory_utilization <= 100 && var.gateway_target_memory_utilization > 0)
    )
    error_message = "'gateway_target_memory_utilization' must be between 0-100."
  }
  validation {
    condition = (
      !var.gateway_enable_autoscaling || 
      var.gateway_target_cpu_utilization != null || 
      var.gateway_target_memory_utilization != null
    )
    error_message = "When 'gateway_enable_autoscaling' is true, at least one of 'gateway_target_cpu_utilization' or 'gateway_target_memory_utilization' must be set."
  }
}

variable "gateway_scale_in_cooldown" {
  description = "Specify scale in cooldown (seconds)"
  type = number
  default = 120
}

variable "gateway_scale_out_cooldown" {
  description = "Specify scale out cooldown (seconds)"
  type = number
  default = 60
}

###########################################################################
#                       DATA SERVICE CONFIGURATION                        #
###########################################################################

variable "enable_dataservice" {
  description = "Specify whether to deploy Data Service"
  type = bool
  default = false
}

variable "dataservice_desired_task" {
  description = "Configure desired number of Data Service Tasks to run."
  type = number
  default = 1
}

variable "dataservice_cpu" {
  description = "Configure cpu for Data Service Tasks."
  type = number
  default = 256
}

variable "dataservice_memory" {
  description = "Configure memory for Data Service Tasks."
  type = number
  default = 1024
}

variable "dataservice_enable_autoscaling" {
  description = "Specify whether to enable autosclaing on Data Service."
  type = bool
  default = false
}

variable "dataservice_min_capacity" {
  description = "Specify minimum number of task to run in Data Service."
  type = number
  default = 1
}

variable "dataservice_max_capacity" {
  description = "Specify maximum number of task to run in Data Service."
  type = number
  default = 3
}

variable "dataservice_target_cpu_utilization" {
  description = "Specify target cpu utilization % that ECS autoscaling should try to maintain for Data Tasks."
  type = number
  default = null
  validation {
    condition = (
      var.dataservice_target_cpu_utilization == null || 
      (var.dataservice_target_cpu_utilization <= 100 && var.dataservice_target_cpu_utilization > 0)
    )
    error_message = "'dataservice_target_cpu_utilization' must be between 0-100."
  }
  validation {
    condition = (
      !var.dataservice_enable_autoscaling || 
      var.dataservice_target_cpu_utilization != null || 
      var.dataservice_target_memory_utilization != null
    )
    error_message = "When 'dataservice_enable_autoscaling' is true, at least one of 'dataservice_target_cpu_utilization' or 'dataservice_target_memory_utilization' must be set."
  }
}

variable "dataservice_target_memory_utilization" {
  description = "Specify target memory utilization % that ECS autoscaling should try to maintain for dataservice tasks."
  type = number
  default = null
  validation {
    condition = (
      var.dataservice_target_memory_utilization == null || 
      (var.dataservice_target_memory_utilization <= 100 && var.dataservice_target_memory_utilization > 0)
    )
    error_message = "'dataservice_target_memory_utilization' must be between 0-100."
  }
  validation {
    condition = (
      !var.dataservice_enable_autoscaling || 
      var.dataservice_target_cpu_utilization != null || 
      var.dataservice_target_memory_utilization != null
    )
    error_message = "When 'dataservice_enable_autoscaling' is true, at least one of 'dataservice_target_cpu_utilization' or 'dataservice_target_memory_utilization' must be set."
  }
}

variable "dataservice_scale_in_cooldown" {
  description = "Specify scale in cooldown (seconds)"
  type = number
  default = 120
}

variable "dataservice_scale_out_cooldown" {
  description = "Specify scale out cooldown (seconds)"
  type = number
  default = 60
}

###########################################################################
#                            REDIS CONFIGURATION                          #
###########################################################################

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
    )
    error_message = "A valid Redis CPU > 0 must be provided if 'type' = 'redis'."
  }
}
variable "redis_memory" {
  description = "Specify Redis memory."
  type        = number
  default     = 256
  validation {
    condition = (
      var.redis_type != "redis" ||
      (
      var.redis_type == "redis" && var.redis_memory > 0
    )
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
  type = string
  default = "standalone"
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

variable "enable_bedrock_access" {
  description = "Enable access to bedrock"
  type        = bool
  default     = false
}

###########################################################################
#                       LOAD BALANCER CONFIGURATION                       #
###########################################################################

variable "create_nlb" {
  description = "Create internal load balancer?"
  type        = bool
  default     = false
}

variable "internal_nlb" {
  description = "Create internal load balancer or interet-facing."
  type        = bool
  default     = true
}

variable "allowed_nlb_cidrs" {
  description = "Provide IP ranges to whitelist in NLB security group. Default 0.0.0.0/0 for internet-facing NLB and VPC_CIDR for internal NLB."
  type        = list(string)
  default     = []
}

variable "tls_certificate_arn" {
  description = "ACM certificate ARN to enable TLS-based listeners."
  type        = string
  default     = ""
}

variable "enable_blue_green" {
  description = "Define whether to configure blue-green deployment for gateway with load balancer"
  type        = bool
  default     = false
  validation {
    condition     = !(var.enable_blue_green && !var.create_nlb)
    error_message = "Must set create_nlb to true for enabling blue green deployment."
  }
}


