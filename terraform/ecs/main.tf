################################################################################
# File: terraform/main.tf
################################################################################

# Fetch AWS Account Id 
data "aws_caller_identity" "current" {}

resource "random_id" "suffix" {
  byte_length = 6
}

# Fetch availability zones in selected region
data "aws_availability_zones" "available" {
  state = "available"
}
data "aws_vpc" "vpc" {
  count = var.create_new_vpc ? 0 : 1
  id    = var.vpc_id
}

locals {

  account_id = data.aws_caller_identity.current.account_id

  region = var.aws_region

  # VPC 
  azs = slice(data.aws_availability_zones.available.names, 0, var.num_az)

  vpc_id   = var.create_new_vpc ? module.vpc[0].vpc_id : var.vpc_id
  vpc_cidr = var.create_new_vpc ? module.vpc[0].vpc_cidr_block : data.aws_vpc.vpc[0].cidr_block

  # Subnets
  private_subnets_cidrs = var.create_new_vpc ? [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + length(local.azs))] : []
  public_subnets_cidrs  = var.create_new_vpc ? [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)] : []

  public_subnet_ids  = var.create_new_vpc ? module.vpc[0].public_subnets : var.public_subnet_ids
  private_subnet_ids = var.create_new_vpc ? module.vpc[0].private_subnets : var.private_subnet_ids

  # Cluster configuration
  cluster_name = var.create_cluster ? module.ecs_cluster[0].name : var.cluster_name
  cluster_arn  = var.create_cluster ? module.ecs_cluster[0].arn : "arn:aws:ecs:${local.region}:${local.account_id}:cluster/${local.cluster_name}"

  capacity_provider_name = var.create_cluster ? module.ecs_cluster[0].autoscaling_capacity_providers["primary_provider"].name : var.capacity_provider_name

  allowed_lb_cidrs = length(var.allowed_lb_cidrs) != 0 ? var.allowed_lb_cidrs : (var.internal_lb ? [local.vpc_cidr] : ["0.0.0.0/0"])

  # Object Storage
  log_store_bucket   = var.object_storage.log_store_bucket
  log_exports_bucket = var.object_storage.log_exports_bucket != null ? var.object_storage.log_exports_bucket : local.log_store_bucket
  finetune_bucket    = var.object_storage.finetune_bucket != null ? var.object_storage.finetune_bucket : local.log_store_bucket

  # Read Environment Variables
  gateway_variables     = jsondecode(file("${path.module}/${var.environment_variables_file_path}")).gateway
  dataservice_variables = jsondecode(file("${path.module}/${var.environment_variables_file_path}")).data-service

  # Read Secrets
  gateway_secrets     = jsondecode(file("${path.module}/${var.secrets_file_path}")).gateway
  dataservice_secrets = jsondecode(file("${path.module}/${var.secrets_file_path}")).data-service

  # Construct environment variables for gateway service
  common_env = {
    CACHE_STORE = var.redis_type
    REDIS_URL = var.redis_type == "redis" ? (
      "redis://redis:6379"
    ) : (var.redis_endpoint)
    REDIS_TLS_ENABLED = var.redis_tls_enabled ? "true" : "false"
    REDIS_MODE        = var.redis_mode
    LOG_STORE_REGION  = var.object_storage.bucket_region
  }

  gateway_env = {
    SERVER_MODE                  = var.server_mode == "both" ? "all" : (var.server_mode == "mcp" ? "mcp" : "")
    MCP_PORT                     = var.server_mode == "both" || var.server_mode == "mcp" ? 8788 : null
    LOG_STORE_GENERATIONS_BUCKET = var.object_storage.log_store_bucket
    DATASERVICE_BASEPATH         = var.dataservice_config.enable_dataservice ? "http://data-service:8081" : null
  }

  dataservice_env = {
    LOG_EXPORTS_BUCKET     = local.log_exports_bucket != "" ? local.log_exports_bucket : local.log_store_bucket
    FINETUNES_BUCKET       = local.finetune_bucket != "" ? local.finetune_bucket : local.log_store_bucket
    AWS_S3_FINETUNE_BUCKET = local.finetune_bucket != "" ? local.finetune_bucket : local.log_store_bucket
  }

  routing_rules = [
    for rule in [
      # For ALB: create host-based routing rules
      var.lb_type == "application" && (var.server_mode == "both" || var.server_mode == "gateway") ? {
        name              = "gateway"
        priority          = 100
        container_port    = 8787
        health_check_path = "/v1/health"
        host      = var.alb_routing_configuration.enable_host_based_routing && var.alb_routing_configuration.gateway_host != "" ? var.alb_routing_configuration.gateway_host : null
        path     = var.alb_routing_configuration.enable_path_based_routing ? var.alb_routing_configuration.gateway_path : ""
      } : null,
      var.lb_type == "application" && (var.server_mode == "both" || var.server_mode == "mcp") ? {
        name              = "mcp"
        priority          = 200
        container_port    = 8788
        health_check_path = "/v1/health"
        host      = var.alb_routing_configuration.enable_host_based_routing && var.alb_routing_configuration.mcp_host != "" ? var.alb_routing_configuration.mcp_host : null
        path     = var.alb_routing_configuration.enable_path_based_routing ? var.alb_routing_configuration.mcp_path : ""
      } : null,
      # For NLB: create a single default rule (NLB doesn't support host-based routing)
      var.lb_type == "network" ? {
        name              = "default"
        priority          = 100
        container_port    = var.server_mode == "both" || var.server_mode == "gateway" ? 8787 : 8788
        health_check_path = "/v1/health"
      } : null,
    ] : rule if rule != null
  ]

  namespace = "portkey"

  gateway_task_role_policies = merge(
    {
      s3_access_policy_arn = aws_iam_policy.s3_access_policy.arn
    },
    var.enable_bedrock_access ? {
      bedrock_access_policy_arn = aws_iam_policy.bedrock_access_policy[0].arn
    } : {}
  )

  data_service_task_role_policies = {
    s3_access_policy_arn = aws_iam_policy.s3_access_policy.arn,
  }
}
