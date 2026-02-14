################################################################################
# File: terraform/aca/variables.tf
################################################################################

#########################################################################
#                           PROJECT DETAILS                             #
#########################################################################

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "portkey-gateway"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "azure_region" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"
}

variable "subscription_id" {
  description = "Azure subscription ID (auto-detected from provider if not provided)"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Name of the resource group (will be created if create_resource_group = true)"
  type        = string
  default     = null
}

variable "create_resource_group" {
  description = "Set to true to create a new resource group"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "environment_variables_file_path" {
  description = "Relative path to environment-variables.json file (optional if environment_variables is provided)"
  type        = string
  default     = null
}

variable "secrets_file_path" {
  description = "Relative path to secrets.json file (optional if secrets is provided)"
  type        = string
  default     = null
}

variable "environment_variables" {
  description = "Environment variables for services (alternative to file path). Provide as a map with 'gateway' and/or 'data-service' keys."
  type = object({
    gateway      = optional(map(string), {})
    data-service = optional(map(string), {})
  })
  default = null

  validation {
    condition = (
      var.environment_variables != null ||
      var.environment_variables_file_path != null
    )
    error_message = "Either environment_variables or environment_variables_file_path must be provided."
  }
}

variable "secrets" {
  description = "Key Vault secret name mappings for services (alternative to file path). Provide as a map with 'gateway' and/or 'data-service' keys. Values are secret names (not values)."
  type = object({
    gateway      = optional(map(string), {})
    data-service = optional(map(string), {})
  })
  default = null

  validation {
    condition = (
      var.secrets != null ||
      var.secrets_file_path != null
    )
    error_message = "Either secrets or secrets_file_path must be provided."
  }
}

#########################################################################
#                         NETWORK CONFIGURATION                         #
#########################################################################

variable "network_mode" {
  description = "Network deployment mode: 'none' (no VNET), 'new' (create VNET), 'existing' (use existing VNET)"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "new", "existing"], var.network_mode)
    error_message = "network_mode must be one of: 'none', 'new', 'existing'."
  }
}

variable "vnet_cidr" {
  description = "CIDR block for new VNET (required if network_mode = 'new')"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vnet_id" {
  description = "Existing VNET ID (required if network_mode = 'existing')"
  type        = string
  default     = null
}

variable "aca_subnet_id" {
  description = "Existing subnet ID for Container Apps (required if network_mode = 'existing')"
  type        = string
  default     = null
}

variable "app_gateway_subnet_id" {
  description = "Existing subnet ID for Application Gateway (required if network_mode = 'existing' and using App Gateway)"
  type        = string
  default     = null
}

variable "private_endpoint_subnet_id" {
  description = "Existing subnet ID for Private Endpoints (required if network_mode = 'existing')"
  type        = string
  default     = null
}

#########################################################################
#                     CONTAINER REGISTRY CONFIGURATION                   #
#########################################################################

variable "registry_type" {
  description = "Container registry type: 'acr' (Azure Container Registry) or 'dockerhub' (Docker Hub)"
  type        = string
  default     = "dockerhub"

  validation {
    condition     = contains(["acr", "dockerhub"], var.registry_type)
    error_message = "registry_type must be one of: 'acr', 'dockerhub'."
  }
}

variable "acr_id" {
  description = "Azure Container Registry ID (required if registry_type = 'acr')"
  type        = string
  default     = null
}

variable "docker_credentials" {
  description = "Docker Hub credentials Key Vault configuration (required if registry_type = 'dockerhub')"
  type = object({
    key_vault_name  = string
    key_vault_rg    = string
    username_secret = string
    password_secret = string
  })
  default = null
}

#########################################################################
#                     CONTAINER IMAGES CONFIGURATION                     #
#########################################################################

variable "gateway_image" {
  description = "Gateway container image configuration"
  type = object({
    image = string
    tag   = string
  })
  default = {
    image = "portkeyai/gateway_enterprise"
    tag   = "latest"
  }
}

#########################################################################
#                     GATEWAY SERVICE CONFIGURATION                      #
#########################################################################

variable "gateway_config" {
  description = "AI Gateway Container App configuration"
  type = object({
    cpu                            = number
    memory                         = string
    min_replicas                   = number
    max_replicas                   = number
    port                           = optional(number, 8787)
    cpu_scale_threshold            = optional(number, 70)   # CPU % threshold (0-100) for scaling
    memory_scale_threshold         = optional(number, null) # Memory % threshold (0-100) for scaling
    http_scale_concurrent_requests = optional(number, 100)  # Concurrent requests per replica for HTTP scaling
  })
  default = {
    cpu                            = 1
    memory                         = "2Gi"
    min_replicas                   = 1
    max_replicas                   = 3
    port                           = 8787
    cpu_scale_threshold            = 70
    memory_scale_threshold         = null
    http_scale_concurrent_requests = 100
  }
}

#########################################################################
#                     MCP SERVICE CONFIGURATION                          #
#########################################################################

variable "mcp_config" {
  description = "MCP Container App configuration"
  type = object({
    cpu                            = number
    memory                         = string
    min_replicas                   = number
    max_replicas                   = number
    port                           = optional(number, 8788)
    cpu_scale_threshold            = optional(number, 70)   # CPU % threshold (0-100) for scaling
    memory_scale_threshold         = optional(number, null) # Memory % threshold (0-100) for scaling
    http_scale_concurrent_requests = optional(number, 100)  # Concurrent requests per replica for HTTP scaling
  })
  default = {
    cpu                            = 1
    memory                         = "2Gi"
    min_replicas                   = 1
    max_replicas                   = 3
    port                           = 8788
    cpu_scale_threshold            = 70
    memory_scale_threshold         = null
    http_scale_concurrent_requests = 100
  }
}

variable "server_mode" {
  description = "Server mode for gateway: 'gateway', 'mcp', or 'all'"
  type        = string
  default     = "gateway"

  validation {
    condition     = contains(["gateway", "mcp", "all"], var.server_mode)
    error_message = "server_mode must be one of: 'gateway', 'mcp', 'all'."
  }
}

#########################################################################
#                     REDIS CONFIGURATION                                #
#########################################################################

variable "redis_config" {
  description = "Redis configuration"
  type = object({
    redis_type = string                         # "redis" (container) or "azure-managed-redis"
    cpu        = optional(number, 0.5)          # Relevant if redis_type = "redis"
    memory     = optional(string, "1Gi")        # Relevant if redis_type = "redis"
    endpoint   = optional(string, "")           # Required if redis_type = "azure-managed-redis"
    tls        = optional(bool, false)          # Set to true if TLS is enabled on Azure Managed Redis
    mode       = optional(string, "standalone") # "standalone" or "cluster"
  })
  default = {
    redis_type = "redis"
    endpoint   = ""
    tls        = false
    mode       = "standalone"
  }

  validation {
    condition     = contains(["redis", "azure-managed-redis"], var.redis_config.redis_type)
    error_message = "redis_config.redis_type must be one of: 'redis', 'azure-managed-redis'."
  }

  validation {
    condition     = contains(["standalone", "cluster"], var.redis_config.mode)
    error_message = "redis_config.mode must be one of: 'standalone', 'cluster'."
  }

  validation {
    condition = (
      var.redis_config.redis_type != "azure-managed-redis" ||
      (var.redis_config.redis_type == "azure-managed-redis" && var.redis_config.endpoint != "")
    )
    error_message = "A valid endpoint must be provided if redis_type = 'azure-managed-redis'."
  }
}

variable "redis_image" {
  description = "Container image to use for Redis (relevant if redis_type = 'redis')"
  type = object({
    image = string
    tag   = string
  })
  default = {
    image = "redis"
    tag   = "7.2-alpine"
  }
}

#########################################################################
#                     STORAGE CONFIGURATION                              #
#########################################################################

variable "storage_config" {
  description = "Azure Blob Storage configuration. If not provided, a new storage account and container will be created."
  type = object({
    resource_group = optional(string)                      # Resource group of existing storage account
    auth_mode      = optional(string, "managed")           # "managed"
    account_name   = optional(string)                      # Existing storage account name (if not provided, one will be created)
    container_name = optional(string, "portkey-log-store") # Container name (defaults to 'portkey-log-store')
  })
  default = {
    auth_mode      = "managed"
    container_name = "portkey-log-store"
  }
}

#########################################################################
#                     INGRESS CONFIGURATION                              #
#########################################################################

variable "ingress_type" {
  description = "Ingress type: 'aca' (built-in) or 'application_gateway'"
  type        = string
  default     = "aca"

  validation {
    condition     = contains(["aca", "application_gateway"], var.ingress_type)
    error_message = "ingress_type must be one of: 'aca', 'application_gateway'."
  }
}

variable "public_ingress" {
  description = "Make the ACA environment publicly accessible (only applies when ingress_type = 'aca'). Ignored when ingress_type = 'application_gateway' — use app_gateway_config.public instead."
  type        = bool
  default     = true
}

#########################################################################
#                 APPLICATION GATEWAY CONFIGURATION                      #
#########################################################################

variable "app_gateway_config" {
  description = "Application Gateway configuration (used if ingress_type = 'application_gateway')"
  type = object({
    sku_name                     = string
    sku_tier                     = string
    capacity                     = number
    enable_waf                   = bool
    public                       = bool
    routing_mode                 = optional(string, "host")       # "host" = host-based routing, "path" = path-based routing
    gateway_host                 = optional(string, "")           # Required if routing_mode = "host"
    mcp_host                     = optional(string, "")           # Required if routing_mode = "host" and server_mode = "all"
    gateway_path                 = optional(string, "/gateway/*") # Path prefix for gateway if routing_mode = "path"
    mcp_path                     = optional(string, "/mcp/*")     # Path prefix for MCP if routing_mode = "path"
    ssl_cert_key_vault_secret_id = optional(string, null)         # Key Vault secret ID for SSL certificate (e.g., https://myvault.vault.azure.net/secrets/my-cert)
    ssl_cert_key_vault_rg        = optional(string, null)         # Resource group of the Key Vault containing the SSL cert (defaults to deployment resource group)
  })
  default = {
    sku_name                     = "Standard_v2"
    sku_tier                     = "Standard_v2"
    capacity                     = 2
    enable_waf                   = false
    public                       = true
    routing_mode                 = "host"
    gateway_host                 = ""
    mcp_host                     = ""
    gateway_path                 = "/gateway/*"
    mcp_path                     = "/mcp/*"
    ssl_cert_key_vault_secret_id = null
    ssl_cert_key_vault_rg        = null
  }

  validation {
    condition     = contains(["host", "path"], var.app_gateway_config.routing_mode)
    error_message = "routing_mode must be one of: 'host', 'path'."
  }
}

#########################################################################
#                     KEY VAULT CONFIGURATION                            #
#########################################################################

variable "secrets_key_vault" {
  description = "Key Vault where app secrets are stored (secrets.json references these)"
  type = object({
    name           = string
    resource_group = string
  })
}

#########################################################################
#                     PORTKEY CONTROL PLANE PRIVATE LINK                  #
#########################################################################

variable "control_plane_private_link" {
  description = "Private Link configuration for Portkey Control Plane"
  type = object({
    outbound = optional(bool, false) # Connect to Portkey Control Plane over Private Link
  })
  default = {
    outbound = false
  }
}
