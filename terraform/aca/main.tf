################################################################################
# File: terraform/aca/main.tf
################################################################################

# Generate random suffix for globally unique names
resource "random_id" "suffix" {
  byte_length = 4
}

# Fetch current Azure client configuration
data "azurerm_client_config" "current" {}

locals {
  # Resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex

  # Resource group
  resource_group_name = var.create_resource_group ? azurerm_resource_group.main[0].name : var.resource_group_name

  # Network configuration
  use_vnet        = var.network_mode != "none"
  create_new_vnet = var.network_mode == "new"

  # Subnet IDs (from new VNET or existing)
  aca_subnet_id              = local.create_new_vnet ? azurerm_subnet.aca[0].id : var.aca_subnet_id
  app_gateway_subnet_id      = local.create_new_vnet ? azurerm_subnet.app_gateway[0].id : var.app_gateway_subnet_id
  private_endpoint_subnet_id = local.create_new_vnet ? azurerm_subnet.private_endpoints[0].id : var.private_endpoint_subnet_id

  # Read environment variables from JSON files or use provided variables
  env_vars_from_file = var.environment_variables_file_path != null ? (
    jsondecode(file("${path.module}/${var.environment_variables_file_path}"))
  ) : null

  secrets_from_file = var.secrets_file_path != null ? (
    jsondecode(file("${path.module}/${var.secrets_file_path}"))
  ) : null

  # Use provided variables if available, fall back to file, default to empty map
  gateway_variables = try(
    var.environment_variables.gateway,
    local.env_vars_from_file.gateway,
    {}
  )

  dataservice_variables = try(
    var.environment_variables["data-service"],
    local.env_vars_from_file["data-service"],
    {}
  )

  gateway_secrets = try(
    var.secrets.gateway,
    local.secrets_from_file.gateway,
    {}
  )

  dataservice_secrets = try(
    var.secrets["data-service"],
    local.secrets_from_file["data-service"],
    {}
  )

  # Common environment variables for all services
  common_env = {
    CACHE_STORE = var.redis_config.redis_type
    REDIS_URL = var.redis_config.redis_type == "redis" ? (
      "redis://redis:6379"
    ) : var.redis_config.endpoint
    REDIS_TLS_ENABLED       = var.redis_config.tls ? "true" : "false"
    REDIS_MODE              = var.redis_config.mode
    LOG_STORE               = "azure"
    AZURE_AUTH_MODE         = var.storage_config.auth_mode
    AZURE_STORAGE_ACCOUNT   = local.storage_account_name
    AZURE_STORAGE_CONTAINER = local.container_name
    AZURE_MANAGED_CLIENT_ID = azurerm_user_assigned_identity.aca.client_id

  }

  # Gateway-specific environment variables
  gateway_env = {
    PORT                 = var.gateway_config.port
    MCP_GATEWAY_BASE_URL = var.server_mode == "all" ? "http://mcp" : null
  }

  # MCP-specific environment variables
  mcp_env = {
    SERVER_MODE = "mcp"
    PORT        = var.mcp_config.port
    MCP_PORT    = var.mcp_config.port
  }

  # Data service-specific environment variables (kept for future use)
  dataservice_env = {
    GATEWAY_BASE_URL = "http://gateway"
  }

  # Container Apps Environment internal/external configuration
  # Always internal when behind App Gateway (App Gateway is the public entry point)
  aca_internal = local.use_vnet && (var.ingress_type == "application_gateway" || !var.public_ingress)

  # Default tags
  default_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  tags = merge(local.default_tags, var.tags)
}

#########################################################################
#                           RESOURCE GROUP                              #
#########################################################################

resource "azurerm_resource_group" "main" {
  count = var.create_resource_group ? 1 : 0

  name     = var.resource_group_name != null ? var.resource_group_name : "rg-${local.name_prefix}"
  location = var.azure_region
  tags     = local.tags
}

# Data source for existing resource group
data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}
