################################################################################
# File: terraform/aca/modules/container-app/main.tf
################################################################################

#########################################################################
#                              LOCALS                                   #
#########################################################################

locals {
  image_url = var.registry_type == "acr" ? (
    "${var.acr_login_server}/${var.container_config.image}:${var.container_config.tag}"
    ) : (
    "${var.docker_registry_url}/${var.container_config.image}:${var.container_config.tag}"
  )

  docker_username        = var.docker_username
  docker_password_kv_url = var.docker_password_kv_url

  env_vars = [
    for k, v in var.container_config.environment_variables : {
      name  = k
      value = v
    } if v != null && v != ""
  ]

  secret_env_vars = [
    for env_var, secret_name in var.container_config.secrets : {
      name        = env_var
      secret_name = secret_name
    }
  ]

  # Container App secrets as Key Vault references (value is null by design)
  secrets = [
    for env_var, secret_name in var.container_config.secrets : {
      name                = secret_name
      key_vault_secret_id = "${var.key_vault_url}secrets/${secret_name}"
      identity            = var.user_assigned_identity_id
    }
  ]

  docker_password_secret = var.registry_type == "dockerhub" && var.docker_password_kv_url != null ? [
    {
      name                = "docker-password"
      key_vault_secret_id = local.docker_password_kv_url
      identity            = var.user_assigned_identity_id
    }
  ] : []

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
        path                    = var.ingress_transport == "tcp" ? null : var.health_probes.path
        port                    = var.ingress_target_port
        initial_delay           = var.health_probes.liveness.initial_delay
        interval_seconds        = var.health_probes.liveness.interval_seconds
        timeout                 = var.health_probes.liveness.timeout
        failure_count_threshold = var.health_probes.liveness.failure_count_threshold
      }

      # Readiness probe
      readiness_probe {
        transport               = var.ingress_transport == "tcp" ? "TCP" : "HTTP"
        path                    = var.ingress_transport == "tcp" ? null : var.health_probes.path
        port                    = var.ingress_target_port
        initial_delay           = var.health_probes.readiness.initial_delay
        interval_seconds        = var.health_probes.readiness.interval_seconds
        timeout                 = var.health_probes.readiness.timeout
        failure_count_threshold = var.health_probes.readiness.failure_count_threshold
      }

      # Startup probe
      startup_probe {
        transport               = var.ingress_transport == "tcp" ? "TCP" : "HTTP"
        path                    = var.ingress_transport == "tcp" ? null : var.health_probes.path
        port                    = var.ingress_target_port
        interval_seconds        = var.health_probes.startup.interval_seconds
        timeout                 = var.health_probes.startup.timeout
        failure_count_threshold = var.health_probes.startup.failure_count_threshold
      }

      dynamic "volume_mounts" {
        for_each = var.secret_volume_mounts
        content {
          name     = volume_mounts.value.name
          path     = volume_mounts.value.mount_path
          sub_path = volume_mounts.value.sub_path
        }
      }
    }

    dynamic "volume" {
      for_each = var.secret_volume_mounts
      content {
        name         = volume.value.name
        storage_type = "Secret"
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
        concurrent_requests = tostring(var.http_scale_concurrent_requests)
      }
    }

    # TCP scaling rule (default - only if no CPU/memory thresholds and TCP transport)
    dynamic "tcp_scale_rule" {
      for_each = var.cpu_scale_threshold == null && var.memory_scale_threshold == null && length(var.scale_rules) == 0 && var.ingress_transport == "tcp" ? [1] : []
      content {
        name                = "tcp-scale"
        concurrent_requests = tostring(var.http_scale_concurrent_requests)
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
}
