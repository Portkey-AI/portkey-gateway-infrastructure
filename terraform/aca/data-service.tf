################################################################################
# File: terraform/aca/data-service.tf
################################################################################

#########################################################################
#                     DATA SERVICE CONTAINER APP                         #
#########################################################################
# NOTE: Data Service is not supported on Azure Container Apps.
# This code is kept for future reference but is disabled.

module "data_service" {
  source = "./modules/container-app"
  count  = 0 # Data Service not supported on Azure

  name                         = "data-service"
  resource_group_name          = local.resource_group_name
  location                     = var.azure_region
  container_app_environment_id = azurerm_container_app_environment.main.id
  user_assigned_identity_id    = azurerm_user_assigned_identity.aca.id
  tags                         = local.tags

  # Container configuration
  container_config = {
    image        = "portkeyai/data-service"
    tag          = "latest"
    cpu          = 0.5
    memory       = "1Gi"
    min_replicas = 1
    max_replicas = 3
    environment_variables = merge(
      local.common_env,
      local.dataservice_env,
      local.dataservice_variables
    )
    secrets = local.dataservice_secrets
  }

  # Registry configuration
  registry_type       = var.registry_type
  acr_login_server    = var.registry_type == "acr" ? data.azurerm_container_registry.acr[0].login_server : null
  docker_registry_url = "docker.io"
  docker_credentials  = var.registry_type == "dockerhub" ? var.docker_credentials : null

  # Ingress configuration - internal only (accessed by gateway)
  ingress_enabled     = true
  ingress_external    = false # Internal only - accessed by gateway
  ingress_target_port = 3000
  ingress_transport   = "auto"

  # Key Vault for secrets
  key_vault_url = data.azurerm_key_vault.secrets.vault_uri

  # Health probes - uses default timings, path is hardcoded to /v1/health
  health_probes = {}

  depends_on = [
    azurerm_role_assignment.secrets_kv_user,
    azurerm_role_assignment.storage_blob_contributor,
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.docker_kv_secrets_user,
    module.gateway
  ]
}
