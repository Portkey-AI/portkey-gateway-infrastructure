################################################################################
# File: terraform/aca/modules/container-app/variables.tf
################################################################################

variable "name" {
  description = "Name of the Container App"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "container_app_environment_id" {
  description = "ID of the Container Apps Environment"
  type        = string
}

variable "user_assigned_identity_id" {
  description = "ID of the user-assigned managed identity"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

#########################################################################
#                     CONTAINER CONFIGURATION                            #
#########################################################################

variable "container_config" {
  description = "Container configuration"
  type = object({
    image                 = string
    tag                   = string
    cpu                   = number
    memory                = string
    min_replicas          = number
    max_replicas          = number
    environment_variables = optional(map(string), {})
    secrets               = optional(map(string), {})
  })
}

variable "key_vault_url" {
  description = "Key Vault URL (e.g., https://myvault.vault.azure.net/)"
  type        = string
  default     = null
}

#########################################################################
#                     REGISTRY CONFIGURATION                             #
#########################################################################

variable "registry_type" {
  description = "Container registry type: 'acr' or 'dockerhub'"
  type        = string
  default     = "dockerhub"

  validation {
    condition     = contains(["acr", "dockerhub"], var.registry_type)
    error_message = "registry_type must be 'acr' or 'dockerhub'."
  }
}

variable "acr_login_server" {
  description = "ACR login server URL (required if registry_type = 'acr')"
  type        = string
  default     = null
}

variable "docker_registry_url" {
  description = "Docker Hub registry URL"
  type        = string
  default     = "docker.io"
}

variable "docker_credentials" {
  description = "Docker Hub credentials Key Vault configuration"
  type = object({
    key_vault_name  = string
    key_vault_rg    = string
    username_secret = string
    password_secret = string
  })
  default = null
}

#########################################################################
#                     INGRESS CONFIGURATION                              #
#########################################################################

variable "ingress_enabled" {
  description = "Enable ingress for the Container App"
  type        = bool
  default     = true
}

variable "ingress_external" {
  description = "Allow external (public) traffic"
  type        = bool
  default     = true
}

variable "ingress_target_port" {
  description = "Target port for ingress traffic"
  type        = number
}

variable "ingress_transport" {
  description = "Transport protocol: 'auto', 'http', 'http2', 'tcp'"
  type        = string
  default     = "auto"
}

#########################################################################
#                     SCALING CONFIGURATION                              #
#########################################################################

variable "scale_rules" {
  description = "Custom scaling rules"
  type = list(object({
    name     = string
    type     = string # http, cpu, memory, custom
    metadata = map(string)
  }))
  default = []
}

variable "http_scale_concurrent_requests" {
  description = "Number of concurrent HTTP requests per replica to trigger scaling. Used when HTTP scaling is active."
  type        = number
  default     = 100
}

variable "cpu_scale_threshold" {
  description = "CPU utilization percentage threshold for scaling (0-100). If set, enables CPU-based scaling."
  type        = number
  default     = null

  validation {
    condition     = var.cpu_scale_threshold == null || (var.cpu_scale_threshold >= 0 && var.cpu_scale_threshold <= 100)
    error_message = "cpu_scale_threshold must be between 0 and 100."
  }
}

variable "memory_scale_threshold" {
  description = "Memory utilization percentage threshold for scaling (0-100). If set, enables memory-based scaling."
  type        = number
  default     = null

  validation {
    condition     = var.memory_scale_threshold == null || (var.memory_scale_threshold >= 0 && var.memory_scale_threshold <= 100)
    error_message = "memory_scale_threshold must be between 0 and 100."
  }
}

#########################################################################
#                     HEALTH PROBES                                      #
#########################################################################

variable "health_probes" {
  description = "Health probe configuration"
  type = object({
    liveness = optional(object({
      initial_delay           = optional(number, 30)
      interval_seconds        = optional(number, 30)
      timeout                 = optional(number, 5)
      failure_count_threshold = optional(number, 3)
    }), {})
    readiness = optional(object({
      initial_delay           = optional(number, 10)
      interval_seconds        = optional(number, 10)
      timeout                 = optional(number, 5)
      failure_count_threshold = optional(number, 3)
    }), {})
    startup = optional(object({
      interval_seconds        = optional(number, 10)
      timeout                 = optional(number, 5)
      failure_count_threshold = optional(number, 3)
    }), {})
  })
  default = {}
}
