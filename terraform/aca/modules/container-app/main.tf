################################################################################
# File: terraform/aca/modules/container-app/main.tf
################################################################################

#########################################################################
#                   DOCKER HUB CREDENTIALS FROM KEY VAULT               #
#########################################################################

# Data source to fetch Docker credentials Key Vault
data "azurerm_key_vault" "docker_creds" {
  count = var.registry_type == "dockerhub" && var.docker_credentials != null ? 1 : 0

  name                = var.docker_credentials.key_vault_name
  resource_group_name = var.docker_credentials.key_vault_rg
}

# Fetch Docker username from Key Vault
# (ACA registry block requires username as plain string, not secret reference)
data "azurerm_key_vault_secret" "docker_username" {
  count = var.registry_type == "dockerhub" && var.docker_credentials != null ? 1 : 0

  name         = var.docker_credentials.username_secret
  key_vault_id = data.azurerm_key_vault.docker_creds[0].id
}

#########################################################################
#                              LOCALS                                   #
#########################################################################

locals {
  # Build full image URL based on registry type
  image_url = var.registry_type == "acr" ? (
    "${var.acr_login_server}/${var.container_config.image}:${var.container_config.tag}"
  ) : (
    "${var.docker_registry_url}/${var.container_config.image}:${var.container_config.tag}"
  )

  # Docker username value from Key Vault
  docker_username = var.registry_type == "dockerhub" && var.docker_credentials != null ? (
    data.azurerm_key_vault_secret.docker_username[0].value
  ) : null

  # Docker password Key Vault secret URL (constructed from credentials config)
  docker_password_kv_url = var.registry_type == "dockerhub" && var.docker_credentials != null ? (
    "${data.azurerm_key_vault.docker_creds[0].vault_uri}secrets/${var.docker_credentials.password_secret}"
  ) : null

  # Convert environment variables to list format (filter out null/empty values)
  env_vars = [
    for k, v in var.container_config.environment_variables : {
      name  = k
      value = v
    } if v != null && v != ""
  ]

  # Convert secrets to list format for secret env vars
  # secrets is a map of ENV_VAR_NAME => secret_name
  secret_env_vars = [
    for env_var, secret_name in var.container_config.secrets : {
      name        = env_var      # ORGANISATIONS_TO_SYNC
      secret_name = secret_name  # org-secret-name
    }
  ]

  # Build secrets list for Container App (Key Vault references)
  secrets = [
    for env_var, secret_name in var.container_config.secrets : {
      name                = secret_name
      key_vault_secret_id = "${var.key_vault_url}secrets/${secret_name}"
      identity            = var.user_assigned_identity_id
    }
  ]

  # Docker password secret (if using Docker Hub)
  docker_password_secret = var.registry_type == "dockerhub" && var.docker_credentials != null ? [
    {
      name                = "docker-password"
      key_vault_secret_id = local.docker_password_kv_url
      identity            = var.user_assigned_identity_id
    }
  ] : []

  # All secrets combined
  all_secrets = concat(local.secrets, local.docker_password_secret)
}

#########################################################################
#                         CONTAINER APP                                  #
#########################################################################

resource "azurerm_container_app" "main" {
  name                         = var.name
  container_app_environment_id = var.container_app_environment_id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  tags = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  # Registry configuration - ACR with managed identity
  dynamic "registry" {
    for_each = var.registry_type == "acr" ? [1] : []
    content {
      server   = var.acr_login_server
      identity = var.user_assigned_identity_id
    }
  }

  # Registry configuration - Docker Hub with credentials from Key Vault
  dynamic "registry" {
    for_each = var.registry_type == "dockerhub" && local.docker_username != null ? [1] : []
    content {
      server               = var.docker_registry_url
      username             = local.docker_username
      password_secret_name = "docker-password"
    }
  }

  # Secrets from Key Vault references
  dynamic "secret" {
    for_each = local.all_secrets
    content {
      name                = secret.value.name
      key_vault_secret_id = secret.value.key_vault_secret_id
      identity            = secret.value.identity
    }
  }

  # Ingress configuration
  dynamic "ingress" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      external_enabled = var.ingress_external
      target_port      = var.ingress_target_port
      transport        = var.ingress_transport

      traffic_weight {
        percentage      = 100
        latest_revision = true
      }
    }
  }

  # Template
  template {
    min_replicas = var.container_config.min_replicas
    max_replicas = var.container_config.max_replicas

    container {
      name   = var.name
      image  = local.image_url
      cpu    = var.container_config.cpu
      memory = var.container_config.memory

      # Environment variables (plain values)
      dynamic "env" {
        for_each = local.env_vars
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      # Secret environment variables (from Key Vault)
      dynamic "env" {
        for_each = local.secret_env_vars
        content {
          name        = env.value.name
          secret_name = env.value.secret_name
        }
      }

      # Liveness probe
      liveness_probe {
        transport               = var.ingress_transport == "tcp" ? "TCP" : "HTTP"
        path                    = var.ingress_transport == "tcp" ? null : "/v1/health"
        port                    = var.ingress_target_port
        initial_delay           = var.health_probes.liveness.initial_delay
        interval_seconds        = var.health_probes.liveness.interval_seconds
        timeout                 = var.health_probes.liveness.timeout
        failure_count_threshold = var.health_probes.liveness.failure_count_threshold
      }

      # Readiness probe
      readiness_probe {
        transport               = var.ingress_transport == "tcp" ? "TCP" : "HTTP"
        path                    = var.ingress_transport == "tcp" ? null : "/v1/health"
        port                    = var.ingress_target_port
        initial_delay           = var.health_probes.readiness.initial_delay
        interval_seconds        = var.health_probes.readiness.interval_seconds
        timeout                 = var.health_probes.readiness.timeout
        failure_count_threshold = var.health_probes.readiness.failure_count_threshold
      }

      # Startup probe
      startup_probe {
        transport               = var.ingress_transport == "tcp" ? "TCP" : "HTTP"
        path                    = var.ingress_transport == "tcp" ? null : "/v1/health"
        port                    = var.ingress_target_port
        interval_seconds        = var.health_probes.startup.interval_seconds
        timeout                 = var.health_probes.startup.timeout
        failure_count_threshold = var.health_probes.startup.failure_count_threshold
      }
    }

    # CPU-based scaling (if threshold provided)
    dynamic "custom_scale_rule" {
      for_each = var.cpu_scale_threshold != null ? [1] : []
      content {
        name             = "cpu-scale"
        custom_rule_type = "cpu"
        metadata = {
          type  = "Utilization"
          value = tostring(var.cpu_scale_threshold)
        }
      }
    }

    # Memory-based scaling (if threshold provided)
    dynamic "custom_scale_rule" {
      for_each = var.memory_scale_threshold != null ? [1] : []
      content {
        name             = "memory-scale"
        custom_rule_type = "memory"
        metadata = {
          type  = "Utilization"
          value = tostring(var.memory_scale_threshold)
        }
      }
    }

    # HTTP scaling rule (default - only if no CPU/memory thresholds and no custom rules)
    dynamic "http_scale_rule" {
      for_each = var.cpu_scale_threshold == null && var.memory_scale_threshold == null && length(var.scale_rules) == 0 && var.ingress_transport != "tcp" ? [1] : []
      content {
        name                = "http-scale"
        concurrent_requests = "100"
      }
    }

    # TCP scaling rule (default - only if no CPU/memory thresholds and TCP transport)
    dynamic "tcp_scale_rule" {
      for_each = var.cpu_scale_threshold == null && var.memory_scale_threshold == null && length(var.scale_rules) == 0 && var.ingress_transport == "tcp" ? [1] : []
      content {
        name                = "tcp-scale"
        concurrent_requests = "100"
      }
    }

    # Custom scaling rules
    dynamic "custom_scale_rule" {
      for_each = [for rule in var.scale_rules : rule if rule.type == "custom"]
      content {
        name             = custom_scale_rule.value.name
        custom_rule_type = custom_scale_rule.value.metadata["type"]
        metadata         = custom_scale_rule.value.metadata
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].container[0].image
    ]
  }
}
