################################################################################
# File: terraform/aca/environments/dev/dev.tfvars
################################################################################

#########################################################################
#                           PROJECT DETAILS                             #
#########################################################################

project_name          = "portkey-gateway"
environment           = "dev"
azure_region          = "eastus"
create_resource_group = true

tags = {
  Environment = "Development"
  Project     = "portkey-gateway"
}

#########################################################################
#                     NETWORK CONFIGURATION                             #
#########################################################################

# Options: "none" (no VNET), "new" (create VNET), "existing" (use existing)
network_mode = "none"

# For new VNET (network_mode = "new"):
# vnet_cidr = "10.0.0.0/16"

# For existing VNET (network_mode = "existing"):
# vnet_id                    = "/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.Network/virtualNetworks/xxx"
# aca_subnet_id              = "/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.Network/virtualNetworks/xxx/subnets/aca"
# app_gateway_subnet_id      = "/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.Network/virtualNetworks/xxx/subnets/appgw"
# private_endpoint_subnet_id = "/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.Network/virtualNetworks/xxx/subnets/pe"

#########################################################################
#                     CONTAINER REGISTRY                                #
#########################################################################

# Options: "acr" or "dockerhub"
registry_type = "dockerhub"

# For ACR:
# acr_id = "/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.ContainerRegistry/registries/xxx"

# For Docker Hub (credentials stored in Key Vault):
docker_credentials = {
  key_vault_name  = "my-keyvault"       # Key Vault name containing docker creds
  key_vault_rg    = "my-resource-group" # Resource group of that Key Vault
  username_secret = "docker-username"   # Secret name for Docker username
  password_secret = "docker-password"   # Secret name for Docker password
}

#########################################################################
#                     SECRETS KEY VAULT                                  #
#########################################################################

# Key Vault where app secrets are stored (referenced in secrets.json)
secrets_key_vault = {
  name           = "my-keyvault"       # Key Vault name
  resource_group = "my-resource-group" # Resource group of that Key Vault
}

#########################################################################
#                     CONTAINER IMAGES                                  #
#########################################################################

gateway_image = {
  image = "portkeyai/gateway_enterprise"
  tag   = "latest"
}

#########################################################################
#                     GATEWAY CONFIGURATION                             #
#########################################################################

gateway_config = {
  cpu          = 1
  memory       = "2Gi"
  min_replicas = 1
  max_replicas = 3
  port         = 8787
}

mcp_config = {
  cpu          = 1
  memory       = "2Gi"
  min_replicas = 1
  max_replicas = 3
  port         = 8788
}

# Options: "gateway", "mcp", "all"
server_mode = "gateway"

#########################################################################
#                     REDIS CONFIGURATION                               #
#########################################################################

# Set redis_type to 'redis' to deploy Redis as a container app,
# or 'azure-managed-redis' to use an external Azure Managed Redis instance.

redis_config = {
  redis_type = "redis"                                                # "redis" (container) or "azure-managed-redis"
}

#########################################################################
#                     STORAGE CONFIGURATION                              #
#########################################################################

# Storage account and container will be created automatically.
# Uncomment and configure to use an existing storage account:

# storage_config = {
#   resource_group = "my-resource-group" # Resource group of storage account
#   auth_mode      = "managed"           # "managed" or "connection_string"
#   account_name   = "mystorageaccount"  # Existing storage account name
#   container_name = "portkey-logs"      # Container name
# }

#########################################################################
#                     INGRESS CONFIGURATION                             #
#########################################################################

# Options: "aca" (built-in) or "application_gateway"
# ingress_type   = "aca"
# public_ingress = true

#########################################################################
#                 APPLICATION GATEWAY (IF USED)                         #
#########################################################################

# app_gateway_config = {
#   sku_name                     = "Standard_v2"
#   sku_tier                     = "Standard_v2"
#   capacity                     = 2
#   enable_waf                   = false
#   public                       = true
#   routing_mode                 = "host"          # "host" or "path"
#   gateway_host                 = "gateway.example.com"   # Used if routing_mode = "host"
#   mcp_host                     = "mcp.example.com"       # Used if routing_mode = "host"
#   gateway_path                 = "/gateway/*"    # Used if routing_mode = "path"
#   mcp_path                     = "/mcp/*"        # Used if routing_mode = "path"
#   ssl_cert_key_vault_secret_id = "https://myvault.vault.azure.net/secrets/my-cert"
# }

#########################################################################
#                 PORTKEY CONTROL PLANE PRIVATE LINK                    #
#########################################################################

# Private Link configuration for Portkey Control Plane (requires VNET)
# outbound = connect to Portkey Control Plane over Private Link
# inbound  = expose this gateway to Portkey Control Plane over Private Link
# control_plane_private_link = {
#   outbound = false
# }

#########################################################################
#                     PATHS TO JSON CONFIG FILES                        #
#########################################################################

environment_variables_file_path = "environments/dev/environment-variables.json"
secrets_file_path               = "environments/dev/secrets.json"
