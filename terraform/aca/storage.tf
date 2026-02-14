################################################################################
# File: terraform/aca/storage.tf
################################################################################

#########################################################################
#                     STORAGE ACCOUNT                                    #
#########################################################################

locals {
  create_storage_account = var.storage_config.account_name == null
  # Storage account name: "st" + project + env + suffix (max 24 chars total)
  # Reserve: 2 (prefix) + 6 (suffix) = 8 chars, leaving 16 for project+env
  storage_name_base_raw  = lower(replace("${var.project_name}${var.environment}", "/[^a-zA-Z0-9]/", ""))
  storage_name_base      = substr(local.storage_name_base_raw, 0, 16) # Truncate to 16 chars
  storage_account_name   = local.create_storage_account ? "st${local.storage_name_base}${random_string.storage_suffix[0].result}" : var.storage_config.account_name
  storage_resource_group = local.create_storage_account ? local.resource_group_name : var.storage_config.resource_group
  container_name         = var.storage_config.container_name
}

# Random suffix for storage account name (storage names must be globally unique)
resource "random_string" "storage_suffix" {
  count   = local.create_storage_account ? 1 : 0
  length  = 6 # Reduced from 8 to help stay within 24 char limit
  special = false
  upper   = false
}

# Create new storage account (if not provided)
resource "azurerm_storage_account" "main" {
  count                      = local.create_storage_account ? 1 : 0
  name                       = local.storage_account_name
  resource_group_name        = local.resource_group_name
  location                   = var.azure_region
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # Enable if deploying in VNET
  public_network_access_enabled = !local.use_vnet

  dynamic "network_rules" {
    for_each = local.use_vnet ? [1] : []
    content {
      default_action             = "Deny"
      virtual_network_subnet_ids = [local.aca_subnet_id]
      bypass                     = ["AzureServices"]
    }
  }

  tags = local.tags
}

# Create blob container
resource "azurerm_storage_container" "main" {
  count                 = local.create_storage_account ? 1 : 0
  name                  = local.container_name
  storage_account_id    = azurerm_storage_account.main[0].id
  container_access_type = "private"
}

# Data source for existing storage account (if provided)
data "azurerm_storage_account" "existing" {
  count               = local.create_storage_account ? 0 : 1
  name                = var.storage_config.account_name
  resource_group_name = var.storage_config.resource_group
}

#########################################################################
#                     RBAC ASSIGNMENTS FOR STORAGE                       #
#########################################################################

# Grant Container Apps managed identity access to the specific blob container
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                = local.create_storage_account ? "${azurerm_storage_account.main[0].id}/blobServices/default/containers/${local.container_name}" : "${data.azurerm_storage_account.existing[0].id}/blobServices/default/containers/${local.container_name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.aca.principal_id
}
