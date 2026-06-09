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

locals {
  gateway_consumed_secret_names = distinct(concat(
    values(local.gateway_secrets),
    values(local.dataservice_secrets),
  ))

  # Docker password secret also needs runtime read access when creds share the secrets vault.
  docker_secret_in_secrets_vault = (
    var.registry_type == "dockerhub" &&
    var.docker_credentials != null &&
    var.docker_credentials.key_vault_name == var.secrets_key_vault.name
  ) ? [var.docker_credentials.password_secret] : []

  secrets_kv_secret_names = toset(concat(
    local.gateway_consumed_secret_names,
    local.docker_secret_in_secrets_vault,
  ))

  dataservice_kv_secret_names = var.dataservice_config.enable_dataservice ? toset(concat(
    distinct(values(local.gateway_secrets)),
    local.docker_secret_in_secrets_vault,
  )) : toset([])
}

# Per-secret access (not vault-wide) for only the secrets the identity consumes.
resource "azurerm_role_assignment" "secrets_kv_user" {
  for_each = local.secrets_kv_secret_names

  scope                = "${data.azurerm_key_vault.secrets.id}/secrets/${each.value}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
}

#########################################################################
#                     DOCKER CREDENTIALS KEY VAULT                       #
#########################################################################

data "azurerm_key_vault" "docker_creds" {
  count = var.registry_type == "dockerhub" && var.docker_credentials != null ? 1 : 0

  name                = var.docker_credentials.key_vault_name
  resource_group_name = var.docker_credentials.key_vault_rg
}

# Resolve Docker Hub credentials at the root (NOT inside the container-app module).
# Reading these here keeps them out of the modules' `depends_on`, so they resolve
# at plan time. If read inside the module, the module-level depends_on defers them
# to apply, leaving the container_app plan partially unknown and triggering the
# azurerm "inconsistent final plan ... for .secret" bug on Key Vault secret refs.
data "azurerm_key_vault_secret" "docker_username" {
  count = var.registry_type == "dockerhub" && var.docker_credentials != null ? 1 : 0

  name         = var.docker_credentials.username_secret
  key_vault_id = data.azurerm_key_vault.docker_creds[0].id
}

locals {
  # Docker username plain value (ACA registry block requires a plain string).
  docker_username = (
    var.registry_type == "dockerhub" && var.docker_credentials != null
  ) ? data.azurerm_key_vault_secret.docker_username[0].value : null

  # Docker password Key Vault secret URL (referenced as an ACA secret).
  docker_password_kv_url = (
    var.registry_type == "dockerhub" && var.docker_credentials != null
  ) ? "${data.azurerm_key_vault.docker_creds[0].vault_uri}secrets/${var.docker_credentials.password_secret}" : null
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
