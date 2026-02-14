################################################################################
# File: terraform/aca/key-vault.tf
################################################################################

#########################################################################
#                     MANAGED IDENTITY FOR CONTAINER APPS                #
#########################################################################

resource "azurerm_user_assigned_identity" "aca" {
  name                = "id-aca-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name

  tags = local.tags
}

#########################################################################
#                     SECRETS KEY VAULT (EXTERNAL)                       #
#########################################################################

# Data source for secrets Key Vault (where app secrets are stored)
data "azurerm_key_vault" "secrets" {
  name                = var.secrets_key_vault.name
  resource_group_name = var.secrets_key_vault.resource_group
}

# Grant Container Apps managed identity access to secrets Key Vault
resource "azurerm_role_assignment" "secrets_kv_user" {
  scope                = data.azurerm_key_vault.secrets.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
}

#########################################################################
#                     DOCKER CREDENTIALS KEY VAULT                       #
#########################################################################

# Data source for Docker credentials Key Vault
data "azurerm_key_vault" "docker_creds" {
  count = var.registry_type == "dockerhub" && var.docker_credentials != null ? 1 : 0

  name                = var.docker_credentials.key_vault_name
  resource_group_name = var.docker_credentials.key_vault_rg
}

# Grant Container Apps managed identity access to Docker credentials Key Vault
# (skip if same as secrets Key Vault)
resource "azurerm_role_assignment" "docker_kv_secrets_user" {
  count = (
    var.registry_type == "dockerhub" &&
    var.docker_credentials != null &&
    var.docker_credentials.key_vault_name != var.secrets_key_vault.name
  ) ? 1 : 0

  scope                = data.azurerm_key_vault.docker_creds[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
}
