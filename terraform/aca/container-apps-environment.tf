################################################################################
# File: terraform/aca/container-apps-environment.tf
################################################################################

#########################################################################
#                 LOG ANALYTICS WORKSPACE                               #
#########################################################################

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.tags
}

#########################################################################
#                 CONTAINER APPS ENVIRONMENT                            #
#########################################################################

resource "azurerm_container_app_environment" "main" {
  name                               = "cae-${local.name_prefix}"
  location                           = var.azure_region
  resource_group_name                = local.resource_group_name
  log_analytics_workspace_id         = azurerm_log_analytics_workspace.main.id
  infrastructure_subnet_id           = local.use_vnet ? local.aca_subnet_id : null
  internal_load_balancer_enabled     = local.use_vnet ? local.aca_internal : null
  zone_redundancy_enabled            = local.use_vnet ? false : null
  public_network_access              = local.use_vnet && local.aca_internal ? "Disabled" : "Enabled"
  infrastructure_resource_group_name = "ME_cae-${local.name_prefix}_${local.resource_group_name}_${var.azure_region}"

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = local.tags

  depends_on = [
    azurerm_subnet.aca
  ]
}

#########################################################################
#                 PRIVATE DNS ZONE FOR INTERNAL ACA ENVIRONMENT        #
#########################################################################
# Internal ACA environments on custom VNETs require manual DNS setup.
# A wildcard A record resolves all app FQDNs to the environment's
# static IP so that App Gateway and other VNET resources can reach them.

resource "azurerm_private_dns_zone" "aca" {
  count = local.use_vnet && local.aca_internal ? 1 : 0

  name                = azurerm_container_app_environment.main.default_domain
  resource_group_name = local.resource_group_name

  tags = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca" {
  count = local.use_vnet && local.aca_internal ? 1 : 0

  name                  = "link-aca-${local.name_prefix}"
  resource_group_name   = local.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.aca[0].name
  virtual_network_id    = local.create_new_vnet ? azurerm_virtual_network.main[0].id : var.vnet_id

  tags = local.tags
}

resource "azurerm_private_dns_a_record" "aca_wildcard" {
  count = local.use_vnet && local.aca_internal ? 1 : 0

  name                = "*"
  zone_name           = azurerm_private_dns_zone.aca[0].name
  resource_group_name = local.resource_group_name
  ttl                 = 300
  records             = [azurerm_container_app_environment.main.static_ip_address]
}

# Note: Storage mounts for config files removed since storage account is external.
# Logs are written directly to Azure Blob Storage via managed identity.
