################################################################################
# File: terraform/aca/modules/container-app/outputs.tf
################################################################################

output "id" {
  description = "The ID of the Container App"
  value       = azurerm_container_app.main.id
}

output "name" {
  description = "The name of the Container App"
  value       = azurerm_container_app.main.name
}

output "fqdn" {
  description = "The FQDN of the Container App"
  value       = var.ingress_enabled ? azurerm_container_app.main.ingress[0].fqdn : null
}

output "latest_revision_name" {
  description = "The name of the latest revision"
  value       = azurerm_container_app.main.latest_revision_name
}

output "latest_revision_fqdn" {
  description = "The FQDN of the latest revision"
  value       = azurerm_container_app.main.latest_revision_fqdn
}

output "outbound_ip_addresses" {
  description = "Outbound IP addresses of the Container App"
  value       = azurerm_container_app.main.outbound_ip_addresses
}
