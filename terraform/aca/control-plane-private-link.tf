################################################################################
# File: terraform/aca/control-plane-private-link.tf
################################################################################

#########################################################################
#                     PORTKEY CONTROL PLANE PRIVATE LINK                  #
#########################################################################

locals {
  control_plane_pl_outbound = var.control_plane_private_link.outbound && local.use_vnet
  control_plane_vnet_id = local.use_vnet ? (
    local.create_new_vnet ? azurerm_virtual_network.main[0].id : var.vnet_id
  ) : null
}

# Private Endpoint to connect to Portkey Control Plane via Private Link
resource "azurerm_private_endpoint" "control_plane" {
  count = local.control_plane_pl_outbound ? 1 : 0

  name                = "pe-controlplane-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name
  subnet_id           = local.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-controlplane-${local.name_prefix}"
    private_connection_resource_id = "/subscriptions/4bec865f-23ea-4d04-be20-3e883cbb3eb1/resourceGroups/privatelink/providers/Microsoft.Network/privateLinkServices/privatelink-proxy-pls"
    is_manual_connection           = true
    request_message                = "Portkey Gateway ${var.project_name}-${var.environment} requesting Private Link to Control Plane"
  }

  tags = local.tags
}

#########################################################################
#                     PRIVATE DNS ZONE                                    #
#########################################################################

# Private DNS Zone for Portkey Control Plane
resource "azurerm_private_dns_zone" "control_plane" {
  count = local.control_plane_pl_outbound ? 1 : 0

  name                = "privatelink-az.portkey.ai"
  resource_group_name = local.resource_group_name

  tags = local.tags
}

# Link the Private DNS Zone to the VNET so containers can resolve the record
resource "azurerm_private_dns_zone_virtual_network_link" "control_plane" {
  count = local.control_plane_pl_outbound ? 1 : 0

  name                  = "vnetlink-controlplane-${local.name_prefix}"
  resource_group_name   = local.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.control_plane[0].name
  virtual_network_id    = local.control_plane_vnet_id
  registration_enabled  = false

  tags = local.tags
}

# A record pointing to the Private Endpoint IP
resource "azurerm_private_dns_a_record" "control_plane" {
  count = local.control_plane_pl_outbound ? 1 : 0

  name                = "azure-cp"
  zone_name           = azurerm_private_dns_zone.control_plane[0].name
  resource_group_name = local.resource_group_name
  ttl                 = 300
  records             = [azurerm_private_endpoint.control_plane[0].private_service_connection[0].private_ip_address]
}

#########################################################################
#                     INBOUND — NATIVE ACA PRIVATE ENDPOINT              #
#########################################################################
# External consumers (e.g., Portkey Control Plane in another subscription)
# can reach the ACA environment via a native Private Endpoint.
#
# No resources are created here — ACA natively supports Private Endpoints.
# The consumer creates a PE targeting the ACA environment resource ID
# (output: container_app_environment_id) with subresource "managedEnvironments".
#
# Traffic is routed to individual apps based on the Host header.
# The consumer must use the FQDN *without* ".internal." and resolve it
# to the PE's private IP via DNS or hosts file.
#   e.g., https://gateway.<env-domain>.eastus.azurecontainerapps.io
#########################################################################
