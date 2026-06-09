################################################################################
# File: terraform/aca/data-service.tf
################################################################################

#########################################################################
#                     DATA SERVICE CONTAINER APP                         #
#########################################################################

resource "azurerm_user_assigned_identity" "aca_dataservice" {
  count = var.dataservice_config.enable_dataservice ? 1 : 0

  name                = "id-aca-ds-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name

  tags = local.tags
}

resource "azurerm_role_assignment" "dataservice_secrets_kv_user" {
  for_each = local.dataservice_kv_secret_names

  scope                = "${data.azurerm_key_vault.secrets.id}/secrets/${each.value}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aca_dataservice[0].principal_id
}

resource "azurerm_role_assignment" "dataservice_docker_kv_secrets_user" {
  count = (
    var.dataservice_config.enable_dataservice &&
    var.registry_type == "dockerhub" &&
    var.docker_credentials != null &&
    var.docker_credentials.key_vault_name != var.secrets_key_vault.name
  ) ? 1 : 0

  scope                = data.azurerm_key_vault.docker_creds[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aca_dataservice[0].principal_id
}

resource "azurerm_role_assignment" "dataservice_acr_pull" {
  count = var.dataservice_config.enable_dataservice && var.registry_type == "acr" ? 1 : 0

  scope                = data.azurerm_container_registry.acr[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aca_dataservice[0].principal_id
}

resource "azurerm_role_definition" "blob_read_write_delete" {
  count = var.dataservice_config.enable_dataservice ? 1 : 0

  name        = "blob-read-write-delete-${local.name_prefix}-${local.name_suffix}"
  scope       = local.storage_account_id
  description = "Read, write, and delete access to blobs for the data service log store"

  permissions {
    actions = []
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
    ]
    not_actions      = []
    not_data_actions = []
  }

  assignable_scopes = [local.storage_account_id]
}

resource "azurerm_role_assignment" "dataservice_storage_blob_read_write" {
  count = var.dataservice_config.enable_dataservice ? 1 : 0

  scope              = local.log_container_scope
  role_definition_id = azurerm_role_definition.blob_read_write_delete[0].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.aca_dataservice[0].principal_id
}

module "data_service" {
  source = "./modules/container-app"
  count  = var.dataservice_config.enable_dataservice ? 1 : 0

  name                         = "data-service"
  resource_group_name          = local.resource_group_name
  location                     = var.azure_region
  container_app_environment_id = azurerm_container_app_environment.main.id
  user_assigned_identity_id    = azurerm_user_assigned_identity.aca_dataservice[0].id
  tags                         = local.tags

  container_config = {
    image        = var.data_service_image.image
    tag          = var.data_service_image.tag
    cpu          = var.dataservice_config.cpu
    memory       = var.dataservice_config.memory
    min_replicas = var.dataservice_config.min_replicas
    max_replicas = var.dataservice_config.max_replicas
    environment_variables = merge(
      local.common_env,
      local.gateway_variables,
      local.dataservice_env
    )
    secrets = local.gateway_secrets
  }

  registry_type          = var.registry_type
  acr_login_server       = var.registry_type == "acr" ? data.azurerm_container_registry.acr[0].login_server : null
  docker_registry_url    = "docker.io"
  docker_username        = local.docker_username
  docker_password_kv_url = local.docker_password_kv_url

  ingress_enabled     = true
  ingress_external    = false
  ingress_target_port = var.dataservice_config.port
  ingress_transport   = "auto"

  cpu_scale_threshold            = var.dataservice_config.cpu_scale_threshold
  memory_scale_threshold         = var.dataservice_config.memory_scale_threshold
  http_scale_concurrent_requests = var.dataservice_config.http_scale_concurrent_requests

  key_vault_url = data.azurerm_key_vault.secrets.vault_uri

  health_probes = {
    path = "/health"
  }

  depends_on = [
    azurerm_role_assignment.dataservice_secrets_kv_user,
    azurerm_role_assignment.dataservice_storage_blob_read_write,
    azurerm_role_assignment.dataservice_acr_pull,
    azurerm_role_assignment.dataservice_docker_kv_secrets_user
  ]
}
