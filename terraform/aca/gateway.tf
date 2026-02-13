################################################################################
# File: terraform/aca/gateway.tf
################################################################################

#########################################################################
#                     ACR CONFIGURATION (IF USED)                        #
#########################################################################

data "azurerm_container_registry" "acr" {
  count = var.registry_type == "acr" ? 1 : 0

  name                = split("/", var.acr_id)[8]
  resource_group_name = split("/", var.acr_id)[4]
}

# Grant ACA identity pull access to ACR
resource "azurerm_role_assignment" "acr_pull" {
  count = var.registry_type == "acr" ? 1 : 0

  scope                = data.azurerm_container_registry.acr[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
}

#########################################################################
#                     GATEWAY CONTAINER APP                              #
#########################################################################

module "gateway" {
  source = "./modules/container-app"
  count  = var.server_mode != "mcp" ? 1 : 0

  name                         = "gateway"
  resource_group_name          = local.resource_group_name
  location                     = var.azure_region
  container_app_environment_id = azurerm_container_app_environment.main.id
  user_assigned_identity_id    = azurerm_user_assigned_identity.aca.id
  tags                         = local.tags

  # Container configuration
  container_config = {
    image        = var.gateway_image.image
    tag          = var.gateway_image.tag
    cpu          = var.gateway_config.cpu
    memory       = var.gateway_config.memory
    min_replicas = var.gateway_config.min_replicas
    max_replicas = var.gateway_config.max_replicas
    environment_variables = merge(
      local.common_env,
      local.gateway_env,
      local.gateway_variables
    )
    secrets = local.gateway_secrets
  }

  # Registry configuration
  registry_type       = var.registry_type
  acr_login_server    = var.registry_type == "acr" ? data.azurerm_container_registry.acr[0].login_server : null
  docker_registry_url = "docker.io"
  docker_credentials  = var.registry_type == "dockerhub" ? var.docker_credentials : null

  # Ingress configuration — always VNET-accessible
  # Public vs private is determined by the ACA environment (internal_load_balancer_enabled)
  ingress_enabled     = true
  ingress_external    = true
  ingress_target_port = var.gateway_config.port
  ingress_transport   = "auto"

  # Scaling configuration
  cpu_scale_threshold            = var.gateway_config.cpu_scale_threshold
  memory_scale_threshold         = var.gateway_config.memory_scale_threshold
  http_scale_concurrent_requests = var.gateway_config.http_scale_concurrent_requests

  # Key Vault for secrets
  key_vault_url = data.azurerm_key_vault.secrets.vault_uri

  # Health probes - uses default timings, path is hardcoded to /v1/health
  health_probes = {}

  depends_on = [
    azurerm_role_assignment.secrets_kv_user,
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.docker_kv_secrets_user
  ]
}

#########################################################################
#                     MCP CONTAINER APP                                  #
#########################################################################

# Separate container app for MCP traffic (server_mode = "all" or "mcp")
module "mcp" {
  source = "./modules/container-app"
  count  = (var.server_mode == "all" || var.server_mode == "mcp") ? 1 : 0

  name                         = "mcp"
  resource_group_name          = local.resource_group_name
  location                     = var.azure_region
  container_app_environment_id = azurerm_container_app_environment.main.id
  user_assigned_identity_id    = azurerm_user_assigned_identity.aca.id
  tags                         = local.tags

  # Container configuration (same image and env as gateway, with MCP overrides)
  container_config = {
    image        = var.gateway_image.image
    tag          = var.gateway_image.tag
    cpu          = var.mcp_config.cpu
    memory       = var.mcp_config.memory
    min_replicas = var.mcp_config.min_replicas
    max_replicas = var.mcp_config.max_replicas
    environment_variables = merge(
      local.common_env,
      local.gateway_env,
      local.gateway_variables,
      local.mcp_env
    )
    secrets = local.gateway_secrets
  }

  # Registry configuration
  registry_type       = var.registry_type
  acr_login_server    = var.registry_type == "acr" ? data.azurerm_container_registry.acr[0].login_server : null
  docker_registry_url = "docker.io"
  docker_credentials  = var.registry_type == "dockerhub" ? var.docker_credentials : null

  # Ingress configuration — always VNET-accessible
  # Public vs private is determined by the ACA environment (internal_load_balancer_enabled)
  ingress_enabled     = true
  ingress_external    = true
  ingress_target_port = var.mcp_config.port
  ingress_transport   = "auto"

  # Scaling configuration
  cpu_scale_threshold            = var.mcp_config.cpu_scale_threshold
  memory_scale_threshold         = var.mcp_config.memory_scale_threshold
  http_scale_concurrent_requests = var.mcp_config.http_scale_concurrent_requests

  # Key Vault for secrets
  key_vault_url = data.azurerm_key_vault.secrets.vault_uri

  # Health probes - uses default timings, path is hardcoded to /v1/health
  health_probes = {}

  depends_on = [
    azurerm_role_assignment.secrets_kv_user,
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.docker_kv_secrets_user
  ]
}
