################################################################################
# File: terraform/aca/vnet.tf
################################################################################

#########################################################################
#                     VIRTUAL NETWORK (CONDITIONAL)                      #
#########################################################################

# Create new VNET if network_mode = "new"
resource "azurerm_virtual_network" "main" {
  count = local.create_new_vnet ? 1 : 0

  name                = "vnet-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name
  address_space       = [var.vnet_cidr]

  tags = local.tags
}

#########################################################################
#                              SUBNETS                                   #
#########################################################################

# Subnet for Container Apps Environment
# Requires minimum /23 CIDR and must be delegated to Microsoft.App/environments
# Private subnet - no default outbound access, uses NAT Gateway
resource "azurerm_subnet" "aca" {
  count = local.create_new_vnet ? 1 : 0

  name                            = "snet-aca"
  resource_group_name             = local.resource_group_name
  virtual_network_name            = azurerm_virtual_network.main[0].name
  address_prefixes                = [cidrsubnet(var.vnet_cidr, 7, 0)] # /23 from /16
  default_outbound_access_enabled = false
  
  # Service endpoints for storage account network rules
  service_endpoints = ["Microsoft.Storage"]

  delegation {
    name = "aca-delegation"

    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Subnet for Application Gateway (if used)
resource "azurerm_subnet" "app_gateway" {
  count = local.create_new_vnet ? 1 : 0

  name                 = "snet-appgw"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 8, 4)] # /24 from /16
}

# Data source for existing app gateway subnet (when network_mode = "existing")
data "azurerm_subnet" "app_gateway_existing" {
  count = var.network_mode == "existing" && var.app_gateway_subnet_id != null ? 1 : 0

  name                 = split("/", var.app_gateway_subnet_id)[10]
  virtual_network_name = split("/", var.app_gateway_subnet_id)[8]
  resource_group_name  = split("/", var.app_gateway_subnet_id)[4]
}

# Subnet for Private Endpoints (Storage, Key Vault, etc.)
# Private subnet - no default outbound access
resource "azurerm_subnet" "private_endpoints" {
  count = local.create_new_vnet ? 1 : 0

  name                              = "snet-pe"
  resource_group_name               = local.resource_group_name
  virtual_network_name              = azurerm_virtual_network.main[0].name
  address_prefixes                  = [cidrsubnet(var.vnet_cidr, 8, 5)] # /24 from /16
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "Disabled"
}

#########################################################################
#                     NAT GATEWAY                                        #
#########################################################################

# Public IP for NAT Gateway
resource "azurerm_public_ip" "nat_gateway" {
  count = local.create_new_vnet ? 1 : 0

  name                = "pip-nat-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = local.tags
}

# NAT Gateway for outbound internet access from private subnets
resource "azurerm_nat_gateway" "main" {
  count = local.create_new_vnet ? 1 : 0

  name                    = "nat-${local.name_prefix}"
  location                = var.azure_region
  resource_group_name     = local.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10

  tags = local.tags
}

# Associate Public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  count = local.create_new_vnet ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.main[0].id
  public_ip_address_id = azurerm_public_ip.nat_gateway[0].id
}

# Associate NAT Gateway with ACA subnet
resource "azurerm_subnet_nat_gateway_association" "aca" {
  count = local.create_new_vnet ? 1 : 0

  subnet_id      = azurerm_subnet.aca[0].id
  nat_gateway_id = azurerm_nat_gateway.main[0].id
}

#########################################################################
#                     NETWORK SECURITY GROUPS                           #
#########################################################################

# NSG for Container Apps subnet
resource "azurerm_network_security_group" "aca" {
  count = local.create_new_vnet ? 1 : 0

  name                = "nsg-aca-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name

  tags = local.tags
}

resource "azurerm_subnet_network_security_group_association" "aca" {
  count = local.create_new_vnet ? 1 : 0

  subnet_id                 = azurerm_subnet.aca[0].id
  network_security_group_id = azurerm_network_security_group.aca[0].id
}

# NSG for Application Gateway subnet
resource "azurerm_network_security_group" "app_gateway" {
  count = local.create_new_vnet ? 1 : 0

  name                = "nsg-appgw-${local.name_prefix}"
  location            = var.azure_region
  resource_group_name = local.resource_group_name

  # Allow inbound HTTP/HTTPS traffic
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow Azure Gateway Manager (required for App Gateway health probes)
  security_rule {
    name                       = "AllowGatewayManager"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  # Allow Azure Load Balancer
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  tags = local.tags
}

resource "azurerm_subnet_network_security_group_association" "app_gateway" {
  count = local.create_new_vnet ? 1 : 0

  subnet_id                 = azurerm_subnet.app_gateway[0].id
  network_security_group_id = azurerm_network_security_group.app_gateway[0].id
}

#########################################################################
#                     DATA SOURCE FOR EXISTING VNET                      #
#########################################################################

data "azurerm_virtual_network" "existing" {
  count = var.network_mode == "existing" ? 1 : 0

  name                = split("/", var.vnet_id)[8]
  resource_group_name = split("/", var.vnet_id)[4]
}
