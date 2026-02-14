################################################################################
# File: terraform/aca/application-gateway.tf
################################################################################

#########################################################################
#                     APPLICATION GATEWAY (OPTIONAL)                     #
#########################################################################

locals {
  appgw_ssl_enabled  = var.app_gateway_config.ssl_cert_key_vault_secret_id != null
  appgw_host_routing = var.app_gateway_config.routing_mode == "host"
  appgw_path_routing = var.app_gateway_config.routing_mode == "path"

  # Compute app gateway private IP based on subnet (works for both new and existing VNET)
  appgw_subnet_prefix = local.create_new_vnet ? azurerm_subnet.app_gateway[0].address_prefixes[0] : (
    var.network_mode == "existing" && var.app_gateway_subnet_id != null ? data.azurerm_subnet.app_gateway_existing[0].address_prefixes[0] : null
  )
  appgw_private_ip = local.appgw_subnet_prefix != null ? cidrhost(local.appgw_subnet_prefix, 10) : null
}

# Managed Identity for App Gateway (needed to access Key Vault for SSL cert)
resource "azurerm_user_assigned_identity" "app_gateway" {
  count = var.ingress_type == "application_gateway" && local.appgw_ssl_enabled ? 1 : 0

  name                = "id-appgw-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name

  tags = local.tags
}

# Look up the Key Vault where the SSL certificate is stored (parsed from the secret URL)
data "azurerm_key_vault" "ssl_cert" {
  count = var.ingress_type == "application_gateway" && local.appgw_ssl_enabled ? 1 : 0

  # Extract vault name from URL: https://<vault-name>.vault.azure.net/secrets/<name>
  name                = split(".", replace(var.app_gateway_config.ssl_cert_key_vault_secret_id, "https://", ""))[0]
  resource_group_name = coalesce(var.app_gateway_config.ssl_cert_key_vault_rg, local.resource_group_name)
}

# Grant App Gateway identity access to the SSL certificate Key Vault
resource "azurerm_role_assignment" "appgw_kv_secrets_user" {
  count = var.ingress_type == "application_gateway" && local.appgw_ssl_enabled ? 1 : 0

  scope                = data.azurerm_key_vault.ssl_cert[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app_gateway[0].principal_id
}

# Public IP for Application Gateway (if public)
resource "azurerm_public_ip" "app_gateway" {
  count = var.ingress_type == "application_gateway" && var.app_gateway_config.public ? 1 : 0

  name                = "pip-appgw-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = local.tags
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  count = var.ingress_type == "application_gateway" ? 1 : 0

  name                = "appgw-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name
  zones               = ["1", "2", "3"]

  sku {
    name     = var.app_gateway_config.enable_waf ? "WAF_v2" : var.app_gateway_config.sku_name
    tier     = var.app_gateway_config.enable_waf ? "WAF_v2" : var.app_gateway_config.sku_tier
    capacity = var.app_gateway_config.capacity
  }

  # Managed identity for Key Vault SSL cert access
  dynamic "identity" {
    for_each = local.appgw_ssl_enabled ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.app_gateway[0].id]
    }
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = local.app_gateway_subnet_id
  }

  #########################################################################
  #                     SSL CERTIFICATE                                    #
  #########################################################################

  dynamic "ssl_certificate" {
    for_each = local.appgw_ssl_enabled ? [1] : []
    content {
      name                = "appgw-ssl-cert"
      key_vault_secret_id = var.app_gateway_config.ssl_cert_key_vault_secret_id
    }
  }

  #########################################################################
  #                     FRONTEND CONFIGURATION                            #
  #########################################################################

  # Public frontend (if enabled)
  dynamic "frontend_ip_configuration" {
    for_each = var.app_gateway_config.public ? [1] : []
    content {
      name                 = "public-frontend"
      public_ip_address_id = azurerm_public_ip.app_gateway[0].id
    }
  }

  # Private frontend (always created when using VNET)
  dynamic "frontend_ip_configuration" {
    for_each = local.use_vnet ? [1] : []
    content {
      name                          = "private-frontend"
      subnet_id                     = local.app_gateway_subnet_id
      private_ip_address_allocation = "Static"
      private_ip_address            = local.appgw_private_ip
    }
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  #########################################################################
  #                     BACKEND POOLS                                     #
  #########################################################################

  # Gateway backend pool
  dynamic "backend_address_pool" {
    for_each = length(module.gateway) > 0 ? [1] : []
    content {
      name  = "gateway-backend"
      fqdns = [module.gateway[0].fqdn]
    }
  }

  # MCP backend pool (if applicable)
  dynamic "backend_address_pool" {
    for_each = length(module.mcp) > 0 ? [1] : []
    content {
      name  = "mcp-backend"
      fqdns = [module.mcp[0].fqdn]
    }
  }

  #########################################################################
  #                     BACKEND HTTP SETTINGS                             #
  #########################################################################

  backend_http_settings {
    name                                = "gateway-http-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true

    probe_name = "gateway-health-probe"
  }

  dynamic "backend_http_settings" {
    for_each = var.server_mode == "all" ? [1] : []
    content {
      name                                = "mcp-http-settings"
      cookie_based_affinity               = "Disabled"
      port                                = 443
      protocol                            = "Https"
      request_timeout                     = 60
      pick_host_name_from_backend_address = true

      probe_name = "mcp-health-probe"
    }
  }

  #########################################################################
  #                     HEALTH PROBES                                     #
  #########################################################################

  probe {
    name                                      = "gateway-health-probe"
    protocol                                  = "Https"
    path                                      = "/v1/health"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  dynamic "probe" {
    for_each = var.server_mode == "all" ? [1] : []
    content {
      name                                      = "mcp-health-probe"
      protocol                                  = "Https"
      path                                      = "/v1/health"
      interval                                  = 30
      timeout                                   = 30
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true
    }
  }

  #########################################################################
  #                     HTTP LISTENERS                                    #
  #########################################################################

  # === HOST-BASED ROUTING: separate listeners per service ===

  # Gateway HTTP listener (public) - host-based
  dynamic "http_listener" {
    for_each = local.appgw_host_routing && var.app_gateway_config.public ? [1] : []
    content {
      name                           = "gateway-http-listener-public"
      frontend_ip_configuration_name = "public-frontend"
      frontend_port_name             = "http-port"
      protocol                       = "Http"
      host_name                      = var.app_gateway_config.gateway_host != "" ? var.app_gateway_config.gateway_host : null
    }
  }

  # Gateway HTTP listener (private) - host-based
  dynamic "http_listener" {
    for_each = local.appgw_host_routing && local.use_vnet ? [1] : []
    content {
      name                           = "gateway-http-listener-private"
      frontend_ip_configuration_name = "private-frontend"
      frontend_port_name             = "http-port"
      protocol                       = "Http"
      host_name                      = var.app_gateway_config.gateway_host != "" ? var.app_gateway_config.gateway_host : null
    }
  }

  # MCP HTTP listener (public) - host-based
  dynamic "http_listener" {
    for_each = local.appgw_host_routing && var.server_mode == "all" && var.app_gateway_config.public ? [1] : []
    content {
      name                           = "mcp-http-listener-public"
      frontend_ip_configuration_name = "public-frontend"
      frontend_port_name             = "http-port"
      protocol                       = "Http"
      host_name                      = var.app_gateway_config.mcp_host != "" ? var.app_gateway_config.mcp_host : null
    }
  }

  # MCP HTTP listener (private) - host-based
  dynamic "http_listener" {
    for_each = local.appgw_host_routing && var.server_mode == "all" && local.use_vnet ? [1] : []
    content {
      name                           = "mcp-http-listener-private"
      frontend_ip_configuration_name = "private-frontend"
      frontend_port_name             = "http-port"
      protocol                       = "Http"
      host_name                      = var.app_gateway_config.mcp_host != "" ? var.app_gateway_config.mcp_host : null
    }
  }

  # === PATH-BASED ROUTING: single listener, route by URL path ===

  # Shared HTTP listener (public) - path-based
  dynamic "http_listener" {
    for_each = local.appgw_path_routing && var.app_gateway_config.public ? [1] : []
    content {
      name                           = "shared-http-listener-public"
      frontend_ip_configuration_name = "public-frontend"
      frontend_port_name             = "http-port"
      protocol                       = "Http"
    }
  }

  # Shared HTTP listener (private) - path-based
  dynamic "http_listener" {
    for_each = local.appgw_path_routing && local.use_vnet ? [1] : []
    content {
      name                           = "shared-http-listener-private"
      frontend_ip_configuration_name = "private-frontend"
      frontend_port_name             = "http-port"
      protocol                       = "Http"
    }
  }

  #########################################################################
  #                     HTTPS LISTENERS (IF SSL CERT PROVIDED)            #
  #########################################################################

  # === HOST-BASED HTTPS ===

  # Gateway HTTPS listener (public) - host-based
  dynamic "http_listener" {
    for_each = local.appgw_ssl_enabled && local.appgw_host_routing && var.app_gateway_config.public ? [1] : []
    content {
      name                           = "gateway-https-listener-public"
      frontend_ip_configuration_name = "public-frontend"
      frontend_port_name             = "https-port"
      protocol                       = "Https"
      ssl_certificate_name           = "appgw-ssl-cert"
      host_name                      = var.app_gateway_config.gateway_host != "" ? var.app_gateway_config.gateway_host : null
    }
  }

  # Gateway HTTPS listener (private) - host-based
  dynamic "http_listener" {
    for_each = local.appgw_ssl_enabled && local.appgw_host_routing && local.use_vnet ? [1] : []
    content {
      name                           = "gateway-https-listener-private"
      frontend_ip_configuration_name = "private-frontend"
      frontend_port_name             = "https-port"
      protocol                       = "Https"
      ssl_certificate_name           = "appgw-ssl-cert"
      host_name                      = var.app_gateway_config.gateway_host != "" ? var.app_gateway_config.gateway_host : null
    }
  }

  # MCP HTTPS listener (public) - host-based
  dynamic "http_listener" {
    for_each = local.appgw_ssl_enabled && local.appgw_host_routing && var.server_mode == "all" && var.app_gateway_config.public ? [1] : []
    content {
      name                           = "mcp-https-listener-public"
      frontend_ip_configuration_name = "public-frontend"
      frontend_port_name             = "https-port"
      protocol                       = "Https"
      ssl_certificate_name           = "appgw-ssl-cert"
      host_name                      = var.app_gateway_config.mcp_host != "" ? var.app_gateway_config.mcp_host : null
    }
  }

  # MCP HTTPS listener (private) - host-based
  dynamic "http_listener" {
    for_each = local.appgw_ssl_enabled && local.appgw_host_routing && var.server_mode == "all" && local.use_vnet ? [1] : []
    content {
      name                           = "mcp-https-listener-private"
      frontend_ip_configuration_name = "private-frontend"
      frontend_port_name             = "https-port"
      protocol                       = "Https"
      ssl_certificate_name           = "appgw-ssl-cert"
      host_name                      = var.app_gateway_config.mcp_host != "" ? var.app_gateway_config.mcp_host : null
    }
  }

  # === PATH-BASED HTTPS ===

  # Shared HTTPS listener (public) - path-based
  dynamic "http_listener" {
    for_each = local.appgw_ssl_enabled && local.appgw_path_routing && var.app_gateway_config.public ? [1] : []
    content {
      name                           = "shared-https-listener-public"
      frontend_ip_configuration_name = "public-frontend"
      frontend_port_name             = "https-port"
      protocol                       = "Https"
      ssl_certificate_name           = "appgw-ssl-cert"
    }
  }

  # Shared HTTPS listener (private) - path-based
  dynamic "http_listener" {
    for_each = local.appgw_ssl_enabled && local.appgw_path_routing && local.use_vnet ? [1] : []
    content {
      name                           = "shared-https-listener-private"
      frontend_ip_configuration_name = "private-frontend"
      frontend_port_name             = "https-port"
      protocol                       = "Https"
      ssl_certificate_name           = "appgw-ssl-cert"
    }
  }

  #########################################################################
  #                     REWRITE RULES (PATH PREFIX STRIPPING)             #
  #########################################################################

  # Strip /gateway prefix before forwarding to backend
  dynamic "rewrite_rule_set" {
    for_each = local.appgw_path_routing ? [1] : []
    content {
      name = "strip-gateway-prefix"

      rewrite_rule {
        name          = "strip-gateway-path"
        rule_sequence = 100

        url {
          path    = "{var_uri_path_1}"
          reroute = false
        }

        condition {
          variable    = "var_uri_path"
          pattern     = "${replace(replace(var.app_gateway_config.gateway_path, "/*", ""), "*", "")}(/.*)$"
          ignore_case = true
          negate      = false
        }
      }
    }
  }

  # Strip /mcp prefix before forwarding to backend
  dynamic "rewrite_rule_set" {
    for_each = local.appgw_path_routing && var.server_mode == "all" ? [1] : []
    content {
      name = "strip-mcp-prefix"

      rewrite_rule {
        name          = "strip-mcp-path"
        rule_sequence = 100

        url {
          path    = "{var_uri_path_1}"
          reroute = false
        }

        condition {
          variable    = "var_uri_path"
          pattern     = "${replace(replace(var.app_gateway_config.mcp_path, "/*", ""), "*", "")}(/.*)$"
          ignore_case = true
          negate      = false
        }
      }
    }
  }

  #########################################################################
  #                     URL PATH MAP (PATH-BASED ROUTING)                 #
  #########################################################################

  # Path map for public listener
  dynamic "url_path_map" {
    for_each = local.appgw_path_routing && var.app_gateway_config.public ? [1] : []
    content {
      name                               = "path-map-public"
      default_backend_address_pool_name  = "gateway-backend"
      default_backend_http_settings_name = "gateway-http-settings"

      path_rule {
        name                       = "gateway-path-rule"
        paths                      = [var.app_gateway_config.gateway_path]
        backend_address_pool_name  = "gateway-backend"
        backend_http_settings_name = "gateway-http-settings"
        rewrite_rule_set_name      = "strip-gateway-prefix"
      }

      dynamic "path_rule" {
        for_each = var.server_mode == "all" ? [1] : []
        content {
          name                       = "mcp-path-rule"
          paths                      = [var.app_gateway_config.mcp_path]
          backend_address_pool_name  = "mcp-backend"
          backend_http_settings_name = "mcp-http-settings"
          rewrite_rule_set_name      = "strip-mcp-prefix"
        }
      }
    }
  }

  # Path map for private listener
  dynamic "url_path_map" {
    for_each = local.appgw_path_routing && local.use_vnet ? [1] : []
    content {
      name                               = "path-map-private"
      default_backend_address_pool_name  = "gateway-backend"
      default_backend_http_settings_name = "gateway-http-settings"

      path_rule {
        name                       = "gateway-path-rule"
        paths                      = [var.app_gateway_config.gateway_path]
        backend_address_pool_name  = "gateway-backend"
        backend_http_settings_name = "gateway-http-settings"
        rewrite_rule_set_name      = "strip-gateway-prefix"
      }

      dynamic "path_rule" {
        for_each = var.server_mode == "all" ? [1] : []
        content {
          name                       = "mcp-path-rule"
          paths                      = [var.app_gateway_config.mcp_path]
          backend_address_pool_name  = "mcp-backend"
          backend_http_settings_name = "mcp-http-settings"
          rewrite_rule_set_name      = "strip-mcp-prefix"
        }
      }
    }
  }

  #########################################################################
  #                     ROUTING RULES — HOST-BASED (HTTP)                 #
  #########################################################################

  # Gateway routing rule (public - HTTP) - host-based
  dynamic "request_routing_rule" {
    for_each = local.appgw_host_routing && var.app_gateway_config.public ? [1] : []
    content {
      name                       = "gateway-routing-rule-public"
      priority                   = 100
      rule_type                  = "Basic"
      http_listener_name         = "gateway-http-listener-public"
      backend_address_pool_name  = "gateway-backend"
      backend_http_settings_name = "gateway-http-settings"
    }
  }

  # Gateway routing rule (private - HTTP) - host-based
  dynamic "request_routing_rule" {
    for_each = local.appgw_host_routing && local.use_vnet ? [1] : []
    content {
      name                       = "gateway-routing-rule-private"
      priority                   = 101
      rule_type                  = "Basic"
      http_listener_name         = "gateway-http-listener-private"
      backend_address_pool_name  = "gateway-backend"
      backend_http_settings_name = "gateway-http-settings"
    }
  }

  # MCP routing rule (public - HTTP) - host-based
  dynamic "request_routing_rule" {
    for_each = local.appgw_host_routing && var.server_mode == "all" && var.app_gateway_config.public ? [1] : []
    content {
      name                       = "mcp-routing-rule-public"
      priority                   = 200
      rule_type                  = "Basic"
      http_listener_name         = "mcp-http-listener-public"
      backend_address_pool_name  = "mcp-backend"
      backend_http_settings_name = "mcp-http-settings"
    }
  }

  # MCP routing rule (private - HTTP) - host-based
  dynamic "request_routing_rule" {
    for_each = local.appgw_host_routing && var.server_mode == "all" && local.use_vnet ? [1] : []
    content {
      name                       = "mcp-routing-rule-private"
      priority                   = 201
      rule_type                  = "Basic"
      http_listener_name         = "mcp-http-listener-private"
      backend_address_pool_name  = "mcp-backend"
      backend_http_settings_name = "mcp-http-settings"
    }
  }

  #########################################################################
  #                     ROUTING RULES — HOST-BASED (HTTPS)                #
  #########################################################################

  # Gateway routing rule (public - HTTPS) - host-based
  dynamic "request_routing_rule" {
    for_each = local.appgw_ssl_enabled && local.appgw_host_routing && var.app_gateway_config.public ? [1] : []
    content {
      name                       = "gateway-routing-rule-https-public"
      priority                   = 110
      rule_type                  = "Basic"
      http_listener_name         = "gateway-https-listener-public"
      backend_address_pool_name  = "gateway-backend"
      backend_http_settings_name = "gateway-http-settings"
    }
  }

  # Gateway routing rule (private - HTTPS) - host-based
  dynamic "request_routing_rule" {
    for_each = local.appgw_ssl_enabled && local.appgw_host_routing && local.use_vnet ? [1] : []
    content {
      name                       = "gateway-routing-rule-https-private"
      priority                   = 111
      rule_type                  = "Basic"
      http_listener_name         = "gateway-https-listener-private"
      backend_address_pool_name  = "gateway-backend"
      backend_http_settings_name = "gateway-http-settings"
    }
  }

  # MCP routing rule (public - HTTPS) - host-based
  dynamic "request_routing_rule" {
    for_each = local.appgw_ssl_enabled && local.appgw_host_routing && var.server_mode == "all" && var.app_gateway_config.public ? [1] : []
    content {
      name                       = "mcp-routing-rule-https-public"
      priority                   = 210
      rule_type                  = "Basic"
      http_listener_name         = "mcp-https-listener-public"
      backend_address_pool_name  = "mcp-backend"
      backend_http_settings_name = "mcp-http-settings"
    }
  }

  # MCP routing rule (private - HTTPS) - host-based
  dynamic "request_routing_rule" {
    for_each = local.appgw_ssl_enabled && local.appgw_host_routing && var.server_mode == "all" && local.use_vnet ? [1] : []
    content {
      name                       = "mcp-routing-rule-https-private"
      priority                   = 211
      rule_type                  = "Basic"
      http_listener_name         = "mcp-https-listener-private"
      backend_address_pool_name  = "mcp-backend"
      backend_http_settings_name = "mcp-http-settings"
    }
  }

  #########################################################################
  #                     ROUTING RULES — PATH-BASED (HTTP)                 #
  #########################################################################

  # Path-based routing rule (public - HTTP)
  dynamic "request_routing_rule" {
    for_each = local.appgw_path_routing && var.app_gateway_config.public ? [1] : []
    content {
      name               = "path-routing-rule-public"
      priority           = 100
      rule_type          = "PathBasedRouting"
      http_listener_name = "shared-http-listener-public"
      url_path_map_name  = "path-map-public"
    }
  }

  # Path-based routing rule (private - HTTP)
  dynamic "request_routing_rule" {
    for_each = local.appgw_path_routing && local.use_vnet ? [1] : []
    content {
      name               = "path-routing-rule-private"
      priority           = 101
      rule_type          = "PathBasedRouting"
      http_listener_name = "shared-http-listener-private"
      url_path_map_name  = "path-map-private"
    }
  }

  #########################################################################
  #                     ROUTING RULES — PATH-BASED (HTTPS)                #
  #########################################################################

  # Path-based routing rule (public - HTTPS)
  dynamic "request_routing_rule" {
    for_each = local.appgw_ssl_enabled && local.appgw_path_routing && var.app_gateway_config.public ? [1] : []
    content {
      name               = "path-routing-rule-https-public"
      priority           = 110
      rule_type          = "PathBasedRouting"
      http_listener_name = "shared-https-listener-public"
      url_path_map_name  = "path-map-public"
    }
  }

  # Path-based routing rule (private - HTTPS)
  dynamic "request_routing_rule" {
    for_each = local.appgw_ssl_enabled && local.appgw_path_routing && local.use_vnet ? [1] : []
    content {
      name               = "path-routing-rule-https-private"
      priority           = 111
      rule_type          = "PathBasedRouting"
      http_listener_name = "shared-https-listener-private"
      url_path_map_name  = "path-map-private"
    }
  }

  #########################################################################
  #                     WAF CONFIGURATION (IF ENABLED)                    #
  #########################################################################

  dynamic "waf_configuration" {
    for_each = var.app_gateway_config.enable_waf ? [1] : []
    content {
      enabled          = true
      firewall_mode    = "Prevention"
      rule_set_type    = "OWASP"
      rule_set_version = "3.2"
    }
  }

  tags = local.tags

  depends_on = [
    module.gateway,
    module.mcp,
    azurerm_role_assignment.appgw_kv_secrets_user
  ]
}
