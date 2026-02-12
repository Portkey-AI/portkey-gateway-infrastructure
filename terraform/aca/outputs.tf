################################################################################
# File: terraform/aca/outputs.tf
################################################################################

#########################################################################
#                     RESOURCE GROUP                                     #
#########################################################################

output "resource_group_name" {
  description = "Name of the resource group"
  value       = local.resource_group_name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = var.create_resource_group ? azurerm_resource_group.main[0].id : data.azurerm_resource_group.existing[0].id
}

#########################################################################
#                     NETWORK                                            #
#########################################################################

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = local.create_new_vnet ? azurerm_virtual_network.main[0].id : var.vnet_id
}

output "aca_subnet_id" {
  description = "ID of the Container Apps subnet"
  value       = local.use_vnet ? local.aca_subnet_id : null
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = local.create_new_vnet ? azurerm_nat_gateway.main[0].id : null
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway"
  value       = local.create_new_vnet ? azurerm_public_ip.nat_gateway[0].ip_address : null
}

#########################################################################
#                     CONTAINER APPS ENVIRONMENT                         #
#########################################################################

output "container_app_environment_id" {
  description = "ID of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.id
}

output "container_app_environment_name" {
  description = "Name of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.name
}

output "container_app_environment_fqdn" {
  description = "Default domain of the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

output "container_app_environment_static_ip" {
  description = "Static IP address of the Container Apps Environment (if VNET integrated)"
  value       = azurerm_container_app_environment.main.static_ip_address
}

#########################################################################
#                     GATEWAY CONTAINER APP                              #
#########################################################################

output "gateway_id" {
  description = "ID of the Gateway Container App"
  value       = length(module.gateway) > 0 ? module.gateway[0].id : null
}

output "gateway_name" {
  description = "Name of the Gateway Container App"
  value       = length(module.gateway) > 0 ? module.gateway[0].name : null
}

output "gateway_fqdn" {
  description = "FQDN of the Gateway Container App"
  value       = length(module.gateway) > 0 ? module.gateway[0].fqdn : null
}

output "gateway_url" {
  description = "Full URL of the Gateway Container App"
  value       = length(module.gateway) > 0 && module.gateway[0].fqdn != null ? "https://${module.gateway[0].fqdn}" : null
}

#########################################################################
#                     MCP CONTAINER APP                                  #
#########################################################################

output "mcp_fqdn" {
  description = "FQDN of the MCP Container App (if deployed)"
  value       = length(module.mcp) > 0 ? module.mcp[0].fqdn : null
}

output "mcp_url" {
  description = "Full URL of the MCP Container App (if deployed)"
  value       = length(module.mcp) > 0 && module.mcp[0].fqdn != null ? "https://${module.mcp[0].fqdn}" : null
}

#########################################################################
#                     APPLICATION GATEWAY                                #
#########################################################################

output "app_gateway_id" {
  description = "ID of the Application Gateway (if deployed)"
  value       = length(azurerm_application_gateway.main) > 0 ? azurerm_application_gateway.main[0].id : null
}

output "app_gateway_public_ip" {
  description = "Public IP address of the Application Gateway (if deployed)"
  value       = length(azurerm_public_ip.app_gateway) > 0 ? azurerm_public_ip.app_gateway[0].ip_address : null
}

output "app_gateway_private_ip" {
  description = "Private IP address of the Application Gateway (if deployed with VNET)"
  value       = length(azurerm_application_gateway.main) > 0 && local.use_vnet ? cidrhost(azurerm_subnet.app_gateway[0].address_prefixes[0], 10) : null
}

#########################################################################
#                     KEY VAULT                                          #
#########################################################################

output "key_vault_id" {
  description = "ID of the secrets Key Vault"
  value       = data.azurerm_key_vault.secrets.id
}

output "key_vault_name" {
  description = "Name of the secrets Key Vault"
  value       = data.azurerm_key_vault.secrets.name
}

output "key_vault_uri" {
  description = "URI of the secrets Key Vault"
  value       = data.azurerm_key_vault.secrets.vault_uri
}

#########################################################################
#                     STORAGE                                            #
#########################################################################

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = local.storage_account_name
}

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = local.create_storage_account ? azurerm_storage_account.main[0].id : data.azurerm_storage_account.existing[0].id
}

output "storage_primary_blob_endpoint" {
  description = "Primary blob endpoint URL"
  value       = local.create_storage_account ? azurerm_storage_account.main[0].primary_blob_endpoint : data.azurerm_storage_account.existing[0].primary_blob_endpoint
}

output "storage_container_name" {
  description = "Name of the blob container"
  value       = local.container_name
}

#########################################################################
#                     MANAGED IDENTITY                                   #
#########################################################################

output "managed_identity_id" {
  description = "ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.aca.id
}

output "managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.aca.principal_id
}

output "managed_identity_client_id" {
  description = "Client ID of the user-assigned managed identity"
  value       = azurerm_user_assigned_identity.aca.client_id
}

#########################################################################
#                     CONTROL PLANE PRIVATE LINK                         #
#########################################################################

output "control_plane_private_endpoint_id" {
  description = "ID of the Portkey Control Plane Private Endpoint"
  value       = length(azurerm_private_endpoint.control_plane) > 0 ? azurerm_private_endpoint.control_plane[0].id : null
}

output "control_plane_private_ip" {
  description = "Private IP address of the Portkey Control Plane Private Endpoint"
  value       = length(azurerm_private_endpoint.control_plane) > 0 ? azurerm_private_endpoint.control_plane[0].private_service_connection[0].private_ip_address : null
}

output "control_plane_private_fqdn" {
  description = "FQDN to reach Portkey Control Plane over Private Link"
  value       = length(azurerm_private_dns_a_record.control_plane) > 0 ? "aws-cp.privatelink-az.portkey.ai" : null
}

#########################################################################
#                     INBOUND PRIVATE ENDPOINT (ACA NATIVE)              #
#########################################################################
# Consumers create a PE targeting container_app_environment_id with
# subresource "managedEnvironments". Use these FQDNs (without .internal.)
# resolved to the PE's private IP.

output "inbound_gateway_fqdn" {
  description = "FQDN for consumers to reach the gateway over Private Endpoint (resolve to PE IP)"
  value       = length(module.gateway) > 0 ? replace(module.gateway[0].fqdn, ".internal.", ".") : null
}

output "inbound_mcp_fqdn" {
  description = "FQDN for consumers to reach MCP over Private Endpoint (resolve to PE IP)"
  value       = length(module.mcp) > 0 ? replace(module.mcp[0].fqdn, ".internal.", ".") : null
}
