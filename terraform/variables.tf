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
variable "gateway_config" {
  description = "Configure details of Gateway Service Tasks"
  type = object({
    desired_task_count = optional(number, 1) # Set desired number of task to run in Gateway Service.
    cpu                = optional(number, 256)
    memory             = optional(number, 1024)
  })
}

variable "gateway_autoscaling" {
  description = "Configure autoscaling for Gateway Service."
  type = object({
    enable_autoscaling        = optional(bool, false)
    autoscaling_max_capacity  = optional(number, 1) # Maximum number of tasks to run in Gateway Service. 
    autoscaling_min_capacity  = optional(number, 1)
    target_cpu_utilization    = optional(number, null)
    target_memory_utilization = optional(number, null)
    scale_in_cooldown         = optional(number, 120)
    scale_out_cooldown        = optional(number, 60)
  })
}

###########################################################################
#                        Data Service Configuration                       #
###########################################################################

variable "dataservice_config" {
  description = "Configure details of Data Service Tasks."
  type = object({
    enable_dataservice = optional(bool, false)
    desired_task_count = optional(number, 1)
    cpu                = optional(number, 256)
    memory             = optional(number, 1024)
  })
}

variable "dataservice_autoscaling" {
  description = "Configure autoscaling for Data Service"
  type = object({
    enable_autoscaling        = optional(bool, false)
    autoscaling_max_capacity  = optional(number, 1)
    autoscaling_min_capacity  = optional(number, 1)
    target_cpu_utilization    = optional(number, null)
    target_memory_utilization = optional(number, null)
    scale_in_cooldown         = optional(number, 120)
    scale_out_cooldown        = optional(number, 60)
  })
  default = {
    enable_autoscaling = false
  }
}

###########################################################################
#                            REDIS CONFIGURATION                          #
###########################################################################

variable "redis_configuration" {
  description = "Configure details of Redis to be used."
  type = object({
    redis_type = string
    cpu        = optional(number, 256)
    memory     = optional(number, 1024)
    endpoint   = optional(string, "")
    tls        = optional(bool, false)
    mode       = optional(string, "standalone")
  })
  default = {
    redis_type = "redis"
  }

  validation {
    condition     = contains(["redis", "aws-elastic-cache"], var.redis_configuration.redis_type)
    error_message = "'redis_type' must be one of: 'redis', 'aws-elastic-cache'."
  }
  validation {
    condition = (
      var.redis_configuration.redis_type != "aws-elastic-cache" ||
      (
      var.redis_configuration.redis_type == "aws-elastic-cache" && var.redis_configuration.endpoint != "")
    )
    error_message = "A valid AWS ElastiCache endpoint must be provided if 'type' = 'aws-elastic-cache'."
  }
  validation {
    condition     = contains(["standalone", "cluster"], var.redis_configuration.mode)
    error_message = "'mode' must be one of: 'standalone', 'cluster'."
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
  default     = true
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


