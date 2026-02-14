# Variables Reference

Complete documentation of all Terraform input variables for the Azure Container Apps deployment.

## Table of Contents

- [Project Details](#project-details)
- [Network](#network)
- [Container Registry](#container-registry)
- [Gateway & MCP Services](#gateway--mcp-services)
- [Redis](#redis)
- [Storage](#storage)
- [Ingress](#ingress)
- [Application Gateway](#application-gateway)
- [Key Vault](#key-vault)
- [Control Plane Private Link](#control-plane-private-link)
- [Config Files](#config-files)

---

## Project Details

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `project_name` | `string` | `"portkey-gateway"` | No | Project name, used for resource naming. All resources are prefixed with `<project_name>-<environment>`. |
| `environment` | `string` | `"dev"` | No | Environment name (e.g., dev, staging, prod). Used in resource naming and tags. |
| `azure_region` | `string` | `"eastus"` | No | Azure region to deploy all resources. |
| `subscription_id` | `string` | `null` | No | Azure subscription ID. Auto-detected from provider if not provided. Required for clone & deploy mode. |
| `resource_group_name` | `string` | `null` | No | Resource group name. Auto-generated as `rg-<project>-<env>` if `create_resource_group = true` and this is `null`. |
| `create_resource_group` | `bool` | `true` | No | `true` = create a new resource group, `false` = use an existing one (must set `resource_group_name`). |
| `tags` | `map(string)` | `{}` | No | Additional tags applied to all resources. Merged with default tags (`Project`, `Environment`, `ManagedBy`). |

---

## Network

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `network_mode` | `string` | `"none"` | No | Controls VNET deployment. See options below. |
| `vnet_cidr` | `string` | `"10.0.0.0/16"` | No | CIDR block for the new VNET. Only used when `network_mode = "new"`. |
| `vnet_id` | `string` | `null` | Conditional | Existing VNET resource ID. **Required** when `network_mode = "existing"`. |
| `aca_subnet_id` | `string` | `null` | Conditional | Existing subnet ID for Container Apps. **Required** when `network_mode = "existing"`. Must have delegation to `Microsoft.App/environments`. Min `/23` CIDR. |
| `app_gateway_subnet_id` | `string` | `null` | Conditional | Existing subnet ID for Application Gateway. **Required** when `network_mode = "existing"` and `ingress_type = "application_gateway"`. Dedicated subnet, min `/24` CIDR. |
| `private_endpoint_subnet_id` | `string` | `null` | Conditional | Existing subnet ID for Private Endpoints. **Required** when `network_mode = "existing"` and using Private Link. |

**Network mode options:**

| Mode | Description | VNET Created? | Subnets |
|------|-------------|---------------|---------|
| `none` | No VNET. Public ACA environment only. | No | None |
| `new` | Creates a new VNET with all required subnets, NSGs, and NAT Gateway. | Yes | ACA, App Gateway, Private Endpoints, NAT Gateway |
| `existing` | Uses an existing VNET. You must provide subnet IDs. | No | User-provided |

**Subnets created when `network_mode = "new"`:**

| Subnet | CIDR (default) | Purpose |
|--------|----------------|---------|
| `snet-aca` | `10.0.0.0/23` | Container Apps Environment (NAT Gateway attached for outbound) |
| `snet-appgw` | `10.0.4.0/24` | Application Gateway |
| `snet-pe` | `10.0.5.0/24` | Private Endpoints |

---

## Container Registry

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `registry_type` | `string` | `"dockerhub"` | No | `acr` = Azure Container Registry (uses managed identity), `dockerhub` = Docker Hub (uses Key Vault credentials). |
| `acr_id` | `string` | `null` | Conditional | Full resource ID of the Azure Container Registry. **Required** when `registry_type = "acr"`. The module grants `AcrPull` role to the managed identity. |
| `docker_credentials` | `object` | `null` | Conditional | Docker Hub credentials configuration. **Required** when `registry_type = "dockerhub"`. |

**`docker_credentials` object:**

| Field | Type | Description |
|-------|------|-------------|
| `key_vault_name` | `string` | Name of the Key Vault containing Docker credentials. |
| `key_vault_rg` | `string` | Resource group of that Key Vault. Can be different from the deployment resource group. |
| `username_secret` | `string` | Name of the Key Vault secret containing the Docker username. |
| `password_secret` | `string` | Name of the Key Vault secret containing the Docker password. |

**Example:**

```hcl
# Azure Container Registry
registry_type = "acr"
acr_id        = "/subscriptions/xxx/resourceGroups/xxx/providers/Microsoft.ContainerRegistry/registries/myregistry"

# Docker Hub
registry_type = "dockerhub"
docker_credentials = {
  key_vault_name  = "my-keyvault"
  key_vault_rg    = "my-rg"
  username_secret = "docker-username"
  password_secret = "docker-password"
}
```

---

## Gateway & MCP Services

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `server_mode` | `string` | `"gateway"` | No | Controls which container apps are deployed. See options below. |
| `gateway_image` | `object` | See below | No | Container image for the Gateway and MCP apps. |
| `gateway_config` | `object` | See below | No | Gateway container sizing and scaling. |
| `mcp_config` | `object` | See below | No | MCP container sizing and scaling (independent from Gateway). |

**Server mode options:**

| Mode | Deploys | Use Case |
|------|---------|----------|
| `gateway` | Gateway only | Standard AI Gateway deployment |
| `mcp` | MCP only | MCP-only deployment |
| `all` | Gateway + MCP (separate container apps) | Full deployment with independent scaling |

**`gateway_image` default:**

```hcl
gateway_image = {
  image = "portkeyai/gateway_enterprise"
  tag   = "latest"
}
```

**`gateway_config` / `mcp_config` fields:**

| Field | Type | Default (Gateway) | Default (MCP) | Description |
|-------|------|-------------------|---------------|-------------|
| `cpu` | `number` | `0.5` | `0.5` | vCPU cores (0.25, 0.5, 1, 2, 4) |
| `memory` | `string` | `"1Gi"` | `"1Gi"` | Memory (must match CPU tier) |
| `min_replicas` | `number` | `1` | `1` | Minimum replica count |
| `max_replicas` | `number` | `3` | `3` | Maximum replica count (auto-scaled) |
| `port` | `number` | `8787` | `8788` | Container listening port |
| `cpu_scale_threshold` | `number` | `70` | `70` | CPU % threshold (0-100) to trigger scaling. Set to `null` to disable and fall back to HTTP scaling. |
| `memory_scale_threshold` | `number` | `null` | `null` | Memory % threshold (0-100) to trigger scaling. Can be used alongside CPU scaling. |
| `http_scale_concurrent_requests` | `number` | `100` | `100` | Concurrent HTTP requests per replica to trigger scaling. Only used when both `cpu_scale_threshold` and `memory_scale_threshold` are `null`. |

**Scaling behavior:**
- **Default**: CPU-based scaling at 70% utilization
- **If `cpu_scale_threshold` set to `null` and `memory_scale_threshold` is `null`**: Falls back to HTTP concurrent requests scaling
- **CPU + Memory together**: Scales when either threshold is reached

**CPU/Memory valid combinations:**

| CPU | Memory Options |
|-----|----------------|
| 0.25 | 0.5Gi |
| 0.5 | 1Gi |
| 1 | 2Gi |
| 2 | 4Gi |
| 4 | 8Gi |

---

## Redis

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `redis_config` | `object` | See below | No | Redis configuration. |
| `redis_image` | `object` | `redis:7.2-alpine` | No | Redis container image (only when `redis_type = "redis"`). |

**`redis_config` fields:**

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `redis_type` | `string` | `"redis"` | No | `redis` = deploy as container app, `azure-managed-redis` = use existing external Redis. |
| `cpu` | `number` | `0.5` | No | CPU for container Redis. Ignored for `azure-managed-redis`. |
| `memory` | `string` | `"1Gi"` | No | Memory for container Redis. Ignored for `azure-managed-redis`. |
| `endpoint` | `string` | `""` | Conditional | Redis connection endpoint. **Required** when `redis_type = "azure-managed-redis"`. |
| `tls` | `bool` | `false` | No | Enable TLS for the Redis connection. Set to `true` for Azure Managed Redis. |
| `mode` | `string` | `"standalone"` | No | `standalone` or `cluster`. Must match your Redis deployment type. |

**Examples:**

```hcl
# Built-in container Redis (dev/test)
redis_config = {
  redis_type = "redis"
  cpu        = 0.5
  memory     = "1Gi"
}

# Azure Managed Redis (production)
redis_config = {
  redis_type = "azure-managed-redis"
  endpoint   = "my-redis.redis.cache.windows.net:6380"
  tls        = true
  mode       = "standalone"
}
```

---

## Storage

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `storage_config` | `object` | See below | No | Azure Blob Storage configuration. If not provided, a new storage account is created automatically. |

**`storage_config` fields:**

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `resource_group` | `string` | `null` | No | Resource group of an existing storage account. If `null`, uses deployment resource group for new storage. |
| `auth_mode` | `string` | `"managed"` | No | `managed` = authenticate via managed identity (recommended)|
| `account_name` | `string` | `null` | No | Name of an existing Azure Storage account. If `null`, a new storage account is created with a globally unique name. |
| `container_name` | `string` | `"portkey-logs"` | No | Blob container name for log storage. Created automatically if using a new storage account. |

**Behavior:**

- **No configuration needed** — A storage account and container are created automatically
- **Provide `account_name`** — Uses existing storage account (must exist in `resource_group`)
- The module automatically grants `Storage Blob Data Contributor` role to the managed identity

**Examples:**

```hcl
# Auto-create storage (default)
storage_config = {}

# Auto-create with custom container name
storage_config = {
  container_name = "my-custom-logs"
}

# Use existing storage account
storage_config = {
  resource_group = "my-rg"
  auth_mode      = "managed"
  account_name   = "myportkeysa"
  container_name = "portkey-logs"
}
```

---

## Ingress

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `ingress_type` | `string` | `"aca"` | No | `aca` = use built-in ACA ingress, `application_gateway` = use Azure Application Gateway. |
| `public_ingress` | `bool` | `true` | No | Make the ACA environment publicly accessible. **Only applies when `ingress_type = "aca"`**. Ignored when using Application Gateway. |

**How ingress and network modes interact:**

| `ingress_type` | `public_ingress` | ACA Environment | Public Access |
|----------------|-------------------|------------------|---------------|
| `aca` | `true` | External | Yes — ACA provides public URL |
| `aca` | `false` | Internal | No — VNET only (requires `network_mode != "none"`) |
| `application_gateway` | *(ignored)* | Internal | Controlled by `app_gateway_config.public` |

---

## Application Gateway

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `app_gateway_config` | `object` | See below | No | Application Gateway configuration. Only used when `ingress_type = "application_gateway"`. |

> **Requires:** `network_mode = "new"` or `"existing"`.

**`app_gateway_config` fields:**

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `sku_name` | `string` | `"Standard_v2"` | No | SKU name. Overridden to `WAF_v2` if `enable_waf = true`. |
| `sku_tier` | `string` | `"Standard_v2"` | No | SKU tier. Overridden to `WAF_v2` if `enable_waf = true`. |
| `capacity` | `number` | `2` | No | Fixed instance count (no autoscaling). |
| `enable_waf` | `bool` | `false` | No | Enable Web Application Firewall (OWASP 3.2 rule set). |
| `public` | `bool` | `true` | No | `true` = create public IP, `false` = private only (VNET access). |
| `routing_mode` | `string` | `"host"` | No | `host` = route by domain name, `path` = route by URL path prefix. |
| `gateway_host` | `string` | `""` | Conditional | Gateway hostname. **Required** when `routing_mode = "host"`. |
| `mcp_host` | `string` | `""` | Conditional | MCP hostname. **Required** when `routing_mode = "host"` and `server_mode = "all"`. |
| `gateway_path` | `string` | `"/gateway/*"` | No | Gateway URL path prefix (when `routing_mode = "path"`). Prefix is stripped before forwarding. |
| `mcp_path` | `string` | `"/mcp/*"` | No | MCP URL path prefix (when `routing_mode = "path"`). Prefix is stripped before forwarding. |
| `ssl_cert_key_vault_secret_id` | `string` | `null` | No | Key Vault secret ID for SSL certificate (e.g., `https://myvault.vault.azure.net/secrets/my-cert`). Enables HTTPS listeners. |
| `ssl_cert_key_vault_rg` | `string` | `null` | No | Resource group of the Key Vault containing the SSL cert. Defaults to the deployment resource group. |

**Features:**
- Deployed across **3 Availability Zones** for high availability
- Both public and private frontend IPs (private is always created when using VNET)
- Health probes to `/v1/health` on port 443 (HTTPS)
- Automatic path prefix stripping for path-based routing

**Examples:**

```hcl
# Host-based routing with SSL
app_gateway_config = {
  sku_name     = "WAF_v2"
  sku_tier     = "WAF_v2"
  capacity     = 2
  enable_waf   = true
  public       = true
  routing_mode = "host"
  gateway_host = "gateway.example.com"
  mcp_host     = "mcp.example.com"
  ssl_cert_key_vault_secret_id = "https://my-kv.vault.azure.net/secrets/my-cert"
  ssl_cert_key_vault_rg        = "my-kv-rg"
}

# Path-based routing, private only
app_gateway_config = {
  sku_name     = "Standard_v2"
  sku_tier     = "Standard_v2"
  capacity     = 2
  enable_waf   = false
  public       = false
  routing_mode = "path"
  gateway_path = "/gateway/*"
  mcp_path     = "/mcp/*"
}
```

---

## Key Vault

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `secrets_key_vault` | `object` | — | **Yes** | Key Vault where application secrets are stored. |

**`secrets_key_vault` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Key Vault name. Secrets referenced in `secrets.json` must exist here. |
| `resource_group` | `string` | Resource group of the Key Vault. Can be different from the deployment resource group. |

The module grants `Key Vault Secrets User` role to the managed identity on this Key Vault.

> **Note:** This can be the same Key Vault as `docker_credentials` or a separate one. The module handles RBAC for both independently.

---

## Control Plane Private Link

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `control_plane_private_link` | `object` | `{ outbound = false }` | No | Private Link configuration for Portkey Control Plane connectivity. |

**`control_plane_private_link` fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `outbound` | `bool` | `false` | Create a Private Endpoint to reach Portkey Control Plane over Private Link instead of the public internet. Requires `network_mode != "none"`. |

When `outbound = true`, the module creates:
- A **Private Endpoint** in the PE subnet connecting to Portkey's Private Link Service
- A **Private DNS Zone** (`privatelink-az.portkey.ai`) linked to the VNET
- An **A record** (`azure-cp`) pointing to the PE's private IP

> The PE connection requires **manual approval** from Portkey. Contact the Portkey team after deployment.

---

## Config Files

Configuration can be provided via JSON files (for clone & deploy) or as direct variables (for module consumption). **One method is required** for both environment variables and secrets.

### File-based Configuration

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `environment_variables_file_path` | `string` | `null` | Conditional | Relative path to `environment-variables.json`. **Required** if `environment_variables` is not provided. |
| `secrets_file_path` | `string` | `null` | Conditional | Relative path to `secrets.json`. **Required** if `secrets` is not provided. |

**`environment-variables.json` format:**

```json
{
  "gateway": {
    "LOG_LEVEL": "info",
    "NODE_ENV": "production"
  },
  "data-service": {
    "LOG_LEVEL": "debug"
  }
}
```

**`secrets.json` format:**

Values are **Key Vault secret names** (not actual values). At runtime, ACA injects the real values via the managed identity.

```json
{
  "gateway": {
    "PORTKEY_CLIENT_AUTH": "portkey-client-auth",
    "ORGANISATIONS_TO_SYNC": "organisations-to-sync"
  },
  "data-service": {
    "PORTKEY_CLIENT_AUTH": "portkey-client-auth",
    "ORGANISATIONS_TO_SYNC": "organisations-to-sync"
  }
}
```

**Usage (clone & deploy):**

```hcl
# In dev.tfvars
environment_variables_file_path = "environments/dev/environment-variables.json"
secrets_file_path               = "environments/dev/secrets.json"
```

### Variable-based Configuration

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `environment_variables` | `object` | `null` | Conditional | Environment variables as a map. **Required** if `environment_variables_file_path` is not provided. |
| `secrets` | `object` | `null` | Conditional | Key Vault secret name mappings. **Required** if `secrets_file_path` is not provided. |

**Object structure:**

```hcl
environment_variables = object({
  gateway      = optional(map(string), {})
  data-service = optional(map(string), {})
})

secrets = object({
  gateway      = optional(map(string), {})
  data-service = optional(map(string), {})
})
```

**Usage (module consumption):**

```hcl
# Pass data directly
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.1.0"

  environment_variables = {
    gateway = {
      LOG_LEVEL             = "info"
      NODE_ENV              = "production"
      ANALYTICS_STORE       = "control_plane"
      AZURE_MANAGED_VERSION = "2019-08-01"
    }
  }
  
  secrets = {
    gateway = {
      PORTKEY_CLIENT_AUTH    = "portkey-client-auth"
      ORGANISATIONS_TO_SYNC  = "organisations-to-sync"
    }
  }
  
  # ...
}

# Or read files from your root module
module "portkey_gateway" {
  source = "..."

  environment_variables = jsondecode(file("${path.root}/config/env-vars.json"))
  secrets               = jsondecode(file("${path.root}/config/secrets.json"))
  
  # ...
}
```
