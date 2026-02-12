# Portkey Gateway - Azure Container Apps Deployment

Deploy Portkey AI Gateway on Azure Container Apps with VNET integration, Application Gateway, Private Link connectivity, and auto-scaling.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration Guides](#configuration-guides)
  - [Server Mode (Gateway + MCP)](#server-mode-gateway--mcp)
  - [Azure Managed Redis](#azure-managed-redis)
  - [Application Gateway Ingress](#application-gateway-ingress)
  - [Private Link Connectivity](#private-link-connectivity)
- [Variables Reference](#variables-reference)
- [Outputs](#outputs)
- [Troubleshooting](#troubleshooting)

## Features

- **VNET Integration**: Private networking with NSGs and NAT Gateway
- **Application Gateway**: WAF-enabled ingress with SSL termination and zone redundancy
- **Auto-scaling**: HTTP-based scaling with configurable min/max replicas
- **Managed Identity**: Secure access to Key Vault and Storage
- **Private Link**: Outbound connectivity to Portkey Control Plane
- **Redis Options**: Built-in container or Azure Managed Redis
- **Multi-service**: Deploy Gateway and MCP independently or together

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Portkey Account** | Sign up at [portkey.ai](https://portkey.ai) |
| **Azure Subscription** | With permissions for ACA, Key Vault, Storage, VNET, App Gateway etc |
| **Terraform** | v1.5+ ([installation](https://developer.hashicorp.com/terraform/install)) |
| **Azure CLI** | Configured with credentials ([installation](https://learn.microsoft.com/cli/azure/install-azure-cli)) |

## Quick Start

> **Looking for module-based deployment?** See [docs/ModuleUsage.md](docs/ModuleUsage.md) for version-controlled deployments.

### 1. Prepare Azure Resources

```bash
# Login to Azure
az login
sub_id=<your-subscription-id>
az account set --subscription ${sub_id}

rg=portkey-rg                                    # Provide name of resource group in which Portkey will be deployed
kv=portkey-kv                                    # Provide Key Vault name

# Create a Key Vault and store your secrets
# Change location as per requirement
az keyvault create --name ${kv} --resource-group ${rg} --location eastus --enable-rbac-authorization true

user_id=$(az ad signed-in-user show --query id -o tsv)

az role assignment create \
  --role "Key Vault Administrator" \
  --assignee $user_id \
  --scope "/subscriptions/${sub_id}/resourceGroups/${rg}/providers/Microsoft.KeyVault/vaults/${kv}"

az keyvault secret set --vault-name ${kv} --name docker-username --value "<docker-username>"         # Docker username shared by Portkey    
az keyvault secret set --vault-name ${kv} --name docker-password --value "<docker-password>"         # Docker password shared by Portkey    
az keyvault secret set --vault-name ${kv} --name portkey-client-auth --value "<portkey-client-auth>" # Shared by Portkey 
az keyvault secret set --vault-name ${kv} --name organisations-to-sync --value "<organisation-id>"   # Provide your Portkey account organisation id

# Create storage account and container for Terraform state
backend_sa=tfstate${sub_id:0:8}                      # Storage account for Terraform state (must be globally unique)

az storage account create \
  --name ${backend_sa} \
  --resource-group ${rg} \
  --location eastus \
  --sku Standard_LRS

az storage container create \
  --name tfstate \
  --account-name ${backend_sa}
```

### 2. Clone the Repository

```bash
git clone https://github.com/Portkey-AI/portkey-gateway-infrastructure
cd portkey-gateway-infrastructure/terraform/aca
```

### 3. Configure Backend
```sh
# Create storage account and container for Terraform state
backend_sa=portkeytfstate                      # Storage account for Terraform state (must be globally unique)

az storage account create \
  --name ${backend_sa} \
  --resource-group ${rg} \
  --location eastus \
  --sku Standard_LRS

az storage container create \
  --name tfstate \
  --account-name ${backend_sa}
```

Update `environments/dev/backend.config` file with resource group name, storage account name and container name:

**Alternative - Local State (for testing only):**

If you prefer local state for development/testing, rename the backend file:

```bash
mv backend.tf backend.tf.disabled
```

### 4. Configure Variables

Edit `environments/dev/dev.tfvars`:

```hcl
# Project
project_name    = "portkey-gateway"
environment     = "dev"
subscription_id = "<your-subscription-id>"
resource_group_name = "portkey-rg"                    # Name of existing resource group in which all resources will be created
# Docker Registry
registry_type = "dockerhub"
docker_credentials = {
  key_vault_name  = <key-vault-name>                  # Name of key vault created in step 1
  key_vault_rg    = <resource-group-name> 
  username_secret = "docker-username"
  password_secret = "docker-password"
}

# Secrets Key Vault
secrets_key_vault = {
  name           = "<secret-kv>"                      # Name of key vault in which secrets.json secrets are created. Can be same key vault storing docker username and password.
  resource_group = "<secret-rg>"
}

# Network (no VNET for simplicity)
network_mode = "none"

# Ingress (built-in ACA ingress)
ingress_type   = "aca"
public_ingress = true

# Redis
redis_config = {
  redis_type = "redis"
}

# Server mode
server_mode = "gateway"                           # Change it to 'mcp' for MCP Gateway and 'all' for both AI and MCP Gateway.

# Config files
environment_variables_file_path = "environments/dev/environment-variables.json"
secrets_file_path               = "environments/dev/secrets.json"
```

Edit `environments/dev/environment-variables.json` to provide environment variables to Portkey application.

**Required variables** (must be included):

```json
{
  "gateway": {
    "LOG_LEVEL": "info",
    "NODE_ENV": "development",
    "ANALYTICS_STORE": "control_plane",
    "AZURE_MANAGED_VERSION": "2019-08-01"
  }
}
```

> **Note**: These four environment variables are required for proper Gateway operation. Add any additional custom environment variables as needed.

Edit `environments/dev/secrets.json`:

```json
{
  "gateway": {
    "PORTKEY_CLIENT_AUTH": "portkey-client-auth",
    "ORGANISATIONS_TO_SYNC": "organisations-to-sync"
  }
}
```

### 5. Deploy

```bash
# Initialize with backend configuration
terraform init -backend-config=environments/dev/backend.config

# Preview changes
terraform plan -var-file=environments/dev/dev.tfvars

# Apply
terraform apply -var-file=environments/dev/dev.tfvars --auto-approve
```

### 6. Verify

```bash
# Get Gateway URL
terraform output gateway_url

# Test health endpoint
curl "$(terraform output -raw gateway_url)/v1/health"

# Test integration with Control Plane
export OPENAI_API_KEY="<your-openai-key>"
export PORTKEY_API_KEY="<your-portkey-key>"

curl "$(terraform output -raw gateway_url)/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "x-portkey-provider: openai" \
  -H "x-portkey-api-key: ${PORTKEY_API_KEY}" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

---

## Configuration Guides

### Server Mode (Gateway + MCP)

Deploy Gateway and MCP as separate, independently scalable container apps.

**Gateway Only (default):**

```hcl
server_mode = "gateway"
```

**MCP Only:**

```hcl
server_mode = "mcp"

mcp_config = {
  cpu          = 1
  memory       = "2Gi"
  min_replicas = 2
  max_replicas = 10
  port         = 8788
}
```

**Gateway + MCP (separate apps):**

```hcl
server_mode = "all"

# Gateway configuration
gateway_config = {
  cpu          = 1
  memory       = "2Gi"
  min_replicas = 2
  max_replicas = 10
  port         = 8787
}

# MCP configuration (independent scaling)
mcp_config = {
  cpu          = 0.5
  memory       = "1Gi"
  min_replicas = 1
  max_replicas = 5
  port         = 8788
}

# Application Gateway routing (host-based)
app_gateway_config = {
  # ...
  routing_mode = "host"
  gateway_host = "gateway.example.com"
  mcp_host     = "mcp.example.com"
}

# Or path-based routing
app_gateway_config = {
  # ...
  routing_mode = "path"
  gateway_path = "/gateway/*"
  mcp_path     = "/mcp/*"
}
```

> **Note:** 
> - Both Gateway and MCP share the same environment variables and secrets (from `gateway` key in JSON).
> - The module automatically adds MCP-specific overrides (`SERVER_MODE=mcp`, `MCP_PORT=8788`).
> - When `server_mode = "all"` with Application Gateway, you must use either host-based or path-based routing.

### Auto-Scaling Configuration

Control how replicas scale based on different metrics.

**Default (HTTP-based scaling):**

Scales based on concurrent HTTP requests (100 per replica):

```hcl
gateway_config = {
  cpu          = 0.5
  memory       = "1Gi"
  min_replicas = 1
  max_replicas = 10
  # No thresholds = HTTP scaling
}
```

**CPU-based scaling:**

Scales when CPU utilization exceeds threshold:

```hcl
gateway_config = {
  cpu                 = 1
  memory              = "2Gi"
  min_replicas        = 2
  max_replicas        = 20
  cpu_scale_threshold = 70  # Scale at 70% CPU
}
```

**Memory-based scaling:**

Scales when memory utilization exceeds threshold:

```hcl
gateway_config = {
  cpu                    = 1
  memory                 = "2Gi"
  min_replicas           = 2
  max_replicas           = 20
  memory_scale_threshold = 80  # Scale at 80% memory
}
```

**Combined CPU + Memory scaling:**

Scales when either threshold is reached:

```hcl
gateway_config = {
  cpu                    = 2
  memory                 = "4Gi"
  min_replicas           = 3
  max_replicas           = 30
  cpu_scale_threshold    = 70  # Scale at 70% CPU
  memory_scale_threshold = 80  # OR 80% memory
}
```

> **Note:** When using CPU/memory thresholds, HTTP-based scaling is disabled. Choose the metric that best matches your workload characteristics.

### Azure Managed Redis

Use Azure Cache for Redis instead of the built-in container for production.

**Quick configuration:**

```hcl
redis_config = {
  redis_type = "azure-managed-redis"
  endpoint   = "rediss://portkey-redis.redis.cache.windows.net:6380"
  tls        = true
  mode       = "standalone"
}
```

**Add Redis password to secrets:**

```json
{
  "gateway": {
    "PORTKEY_CLIENT_AUTH": "portkey-client-auth",
    "ORGANISATIONS_TO_SYNC": "organisations-to-sync",
    "REDIS_PASSWORD": "redis-password"
  }
}
```

> **For detailed setup including:** creating Redis, storing passwords in Key Vault, Private Endpoint configuration, and module examples, see **[docs/ExternalRedis.md](docs/ExternalRedis.md)**.

---

## Storage Configuration

By default, Terraform automatically creates a new Azure Storage Account and container for storing LLM request/response logs.

### Using Auto-Created Storage (Default)

No configuration needed. Terraform will:
- Create a Storage Account with a globally unique name
- Create a container named `portkey-log-store`
- Configure managed identity authentication
- Apply proper RBAC permissions

**Optional: Customize container name:**

```hcl
storage_config = {
  container_name = "my-custom-container-name"
}
```

### Using Existing Storage Account

If you already have a storage account and container:

```hcl
storage_config = {
  resource_group = "my-storage-account-rg"
  auth_mode      = "managed"
  account_name   = "my-storage-account-name"
  container_name = "my-container-name"
}
```

**Prerequisites:**
- Storage account must exist
- Container must exist
- The Terraform managed identity needs `Storage Blob Data Contributor` role on the container (automatically assigned by Terraform)

**Authentication modes:**
- `managed` (recommended) - Uses managed identity with RBAC to access Blob Storage

---

## Application Gateway Ingress

Deploy Azure Application Gateway with WAF, SSL termination, and zone redundancy etc.

> **Requires:** `network_mode = "new"` or `"existing"` (VNET is mandatory)

**Basic Configuration:**

```hcl
ingress_type = "application_gateway"

app_gateway_config = {
  sku_name     = "Standard_v2"  # or "WAF_v2"
  sku_tier     = "Standard_v2"  # or "WAF_v2"
  capacity     = 2
  enable_waf   = false          # Enables OWASP 3.2 rules
  public       = true           # false = private only
  routing_mode = "host"
  gateway_host = "gateway.example.com"
}
```

**Host-based Routing:**

Route by domain name. Each service gets its own hostname.

```hcl
app_gateway_config = {
  # ...
  routing_mode = "host"
  gateway_host = "gateway.example.com"
  mcp_host     = "mcp.example.com"  # if server_mode = "all"
}
```

Configure DNS:
```
gateway.example.com  A  <app-gateway-public-ip>
mcp.example.com      A  <app-gateway-public-ip>
```

**Path-based Routing:**

Route by URL path. Single domain, different paths for each service.

```hcl
app_gateway_config = {
  # ...
  routing_mode = "path"
  gateway_path = "/gateway/*"
  mcp_path     = "/mcp/*"
}
```

Request to `/gateway/v1/chat` → forwarded to Gateway as `/v1/chat` (prefix stripped automatically)

**SSL Certificate:**

Enable HTTPS with a certificate from Key Vault.

**Step 1: Import certificate:**

```bash
az keyvault certificate import \
  --vault-name my-ssl-kv \
  --name my-ssl-cert \
  --file certificate.pfx \
  --password "<pfx-password>"
```

**Step 2: Configure in tfvars:**

```hcl
app_gateway_config = {
  # ...
  ssl_cert_key_vault_secret_id = "https://my-ssl-kv.vault.azure.net/secrets/my-ssl-cert"
  ssl_cert_key_vault_rg        = "my-ssl-kv-rg"  # Optional, defaults to deployment RG
}
```

The module automatically:
- Creates a managed identity for App Gateway
- Grants `Key Vault Secrets User` access
- Configures HTTPS listeners (443) alongside HTTP (80)

**Private Application Gateway:**

Deploy without a public IP for VNET-only access.

```hcl
app_gateway_config = {
  # ...
  public = false
}
```

### Private Link Connectivity

Enable private connectivity between your Gateway and Portkey Control Plane using Azure Private Link.

- **Outbound**: Your Gateway → Portkey Control Plane (private connection)
- **Inbound**: Portkey Control Plane → Your Gateway (private connection)

For complete setup instructions, see **[docs/PrivateConnectivity.md](docs/PrivateConnectivity.md)**.

---

## Variables Reference

For complete variable documentation, see **[docs/Variables.md](docs/Variables.md)**.

---

## Outputs

| Output | Description |
|--------|-------------|
| **Gateway** | |
| `gateway_url` | Full HTTPS URL of the Gateway |
| `gateway_fqdn` | FQDN of the Gateway Container App |
| `mcp_url` | Full HTTPS URL of the MCP service |
| **Application Gateway** | |
| `app_gateway_public_ip` | Public IP of Application Gateway |
| `app_gateway_private_ip` | Private IP of Application Gateway |
| **Network** | |
| `vnet_id` | Virtual Network ID |
| `nat_gateway_public_ip` | NAT Gateway public IP (outbound) |
| **ACA Environment** | |
| `container_app_environment_id` | ACA Environment ID (for inbound PE) |
| **Control Plane** | |
| `control_plane_private_ip` | Private IP for Control Plane PE |
| **Inbound** | |
| `inbound_gateway_fqdn` | FQDN for consumers via PE |
| `inbound_mcp_fqdn` | MCP FQDN for consumers via PE |
| **Identity** | |
| `managed_identity_client_id` | Managed identity client ID |

---

### Cleanup

```bash
terraform destroy -var-file=environments/prod/prod.tfvars
```