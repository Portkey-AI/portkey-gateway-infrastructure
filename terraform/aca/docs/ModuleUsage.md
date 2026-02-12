# Module-Based Deployment

Use the Portkey Gateway Terraform module to deploy infrastructure as code in your own Terraform project. This approach is recommended for production deployments, multi-environment management, and version-controlled upgrades.

## Table of Contents

- [Benefits](#benefits)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Backend Configuration](#backend-configuration)
- [Module Configuration](#module-configuration)
- [Complete Examples](#complete-examples)
- [Multi-Environment Setup](#multi-environment-setup)
- [Version Pinning](#version-pinning)
- [Upgrading](#upgrading)

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Portkey Account** | Sign up at [portkey.ai](https://portkey.ai) |
| **Azure Subscription** | With permissions for ACA, Key Vault, Storage, VNET, App Gateway |
| **Terraform** | v1.5+ ([installation](https://developer.hashicorp.com/terraform/install)) |
| **Azure CLI** | Configured with credentials ([installation](https://learn.microsoft.com/cli/azure/install-azure-cli)) |

## Quick Start

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

```

### 2. Create Your Terraform Project

```bash
mkdir portkey-gateway-deployment
cd portkey-gateway-deployment
```

Create `main.tf`:

```hcl
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "<your-subscription-id>"                    # Replace with Azure subscription id in which gateway will be deployed
}

# Replace vX.Y.Z with the desired module version (e.g., v1.0.0)
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=vX.Y.Z"

  # Project
  project_name = "portkey-gateway"
  environment  = "dev"
  resource_group_name = "portkey-rg"                    # Name of existing resource group in which all resources will be created. To create new set create_resource_group = true

  # Docker Registry
  registry_type = "dockerhub"
  docker_credentials = {
    key_vault_name  = "portkey-kv"
    key_vault_rg    = "portkey-rg"
    username_secret = "docker-username"
    password_secret = "docker-password"
  }

  # Secrets Key Vault
  secrets_key_vault = {
    name           = "portkey-kv"
    resource_group = "portkey-rg"
  }

  # Configuration
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

  # Network
  network_mode = "none"

  # Ingress
  ingress_type = "aca"


  # Redis (built-in)
  redis_config = {
    redis_type = "redis"
  }

  server_mode = "gateway"
}

output "gateway_url" {
  value = module.portkey_gateway.gateway_url
}

output "app_gateway_public_ip" {
  value = module.portkey_gateway.app_gateway_public_ip
}
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 4. Verify

```bash
terraform output gateway_url
curl "$(terraform output -raw gateway_url)/v1/health"
```

## Project Structure

Your Terraform project directory:

```
portkey-gateway-deployment/
├── main.tf              # Module + backend configuration
├── variables.tf         # (optional) Your own variables
├── terraform.tfvars     # (optional) Variable values
├── outputs.tf           # (optional) Additional outputs
└── backend.config       # (optional) Backend config file
```

## Remote Backend Configuration
Create Azure Blob Storage and Blob Container to store terraform state.
```sh
rg=portkey-rg                                        # Resource group to create remote backend blob store
backend_sa=tfstatesa                                 # Storage account for Terraform state (must be globally unique)

az storage account create \
  --name ${backend_sa} \
  --resource-group ${rg} \
  --location eastus \
  --sku Standard_LRS

az storage container create \
  --name tfstate \
  --account-name ${backend_sa}
```
Create a `backend.config` file to configure remote state storage

```hcl
resource_group_name  = "portkey-rg"
storage_account_name = "tfstatesa"
container_name       = "tfstate"
key                  = "portkey-gateway/dev.tfstate"
```

In `main.tf`:

```hcl
terraform {
  backend "azurerm" {}  
}
```

Initialize with the config file:

```bash
terraform init -backend-config=backend.config
```

## Module Configuration

### Using JSON Files

If you prefer to keep configuration in JSON files (like the clone & deploy approach):

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"

  # Read from files in your project
  environment_variables = jsondecode(file("${path.root}/config/environment-variables.json"))
  secrets               = jsondecode(file("${path.root}/config/secrets.json"))
  
  # ... other variables
}
```

### Using Inline Variables

Pass configuration directly as HCL:

```hcl
module "portkey_gateway" {
  source = "..."

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
}
```

### Using Your Own Variables

Create `variables.tf`:

```hcl
variable "environment" {
  type = string
}

variable "kv_name" {
  type = string
}
```

Create `terraform.tfvars`:

```hcl
environment = "prod"
kv_name     = "my-portkey-kv"
```

Use in `main.tf`:

```hcl
module "portkey_gateway" {
  source = "..."

  environment = var.environment
  
  secrets_key_vault = {
    name           = var.kv_name
    resource_group = "my-rg"
  }
  
  # ...
}
```

## Complete Examples

### Production with All Features

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"

  project_name = "portkey-gateway"
  environment  = "prod"

  tags = {
    CostCenter = "Engineering"
    Owner      = "Platform Team"
  }

  registry_type = "dockerhub"
  docker_credentials = {
    key_vault_name  = "portkey-prod-kv"
    key_vault_rg    = "portkey-prod-rg"
    username_secret = "docker-username"
    password_secret = "docker-password"
  }

  secrets_key_vault = {
    name           = "portkey-prod-kv"
    resource_group = "portkey-prod-rg"
  }

  environment_variables = {
    gateway = {
      LOG_LEVEL                 = "info"
      NODE_ENV                  = "production"
      ANALYTICS_STORE           = "control_plane"
      AZURE_MANAGED_VERSION     = "2019-08-01"
      ALBUS_BASEPATH            = "https://azure-cp.privatelink-az.portkey.ai/albus"
      CONTROL_PLANE_BASEPATH    = "https://azure-cp.privatelink-az.portkey.ai/api/v1"
      SOURCE_SYNC_API_BASEPATH  = "https://azure-cp.privatelink-az.portkey.ai/api/v1/sync"
      CONFIG_READER_PATH        = "https://azure-cp.privatelink-az.portkey.ai/api/model-configs"
    }
  }

  secrets = {
    gateway = {
      PORTKEY_CLIENT_AUTH    = "portkey-client-auth"
      ORGANISATIONS_TO_SYNC  = "organisations-to-sync"
    }
  }

  network_mode = "new"
  vnet_cidr    = "10.0.0.0/16"

  # Gateway + MCP
  server_mode = "all"
  
  gateway_config = {
    cpu                    = 2
    memory                 = "4Gi"
    min_replicas           = 3
    max_replicas           = 20
    cpu_scale_threshold    = 70   # Scale at 70% CPU
    memory_scale_threshold = 80   # OR 80% memory
  }

  mcp_config = {
    cpu                    = 1
    memory                 = "2Gi"
    min_replicas           = 2
    max_replicas           = 10
    cpu_scale_threshold    = 75   # Scale at 75% CPU
  }

  # Application Gateway with SSL
  ingress_type = "application_gateway"
  app_gateway_config = {
    sku_name                     = "WAF_v2"
    sku_tier                     = "WAF_v2"
    capacity                     = 3
    enable_waf                   = true
    public                       = true
    routing_mode                 = "host"
    gateway_host                 = "gateway.example.com"
    mcp_host                     = "mcp.example.com"
    ssl_cert_key_vault_secret_id = "https://ssl-kv.vault.azure.net/secrets/wildcard-cert"
    ssl_cert_key_vault_rg        = "ssl-rg"
  }

  # Azure Managed Redis
  redis_config = {
    redis_type = "azure-managed-redis"
    endpoint   = "prod-redis.redis.cache.windows.net:6380"
    tls        = true
    mode       = "cluster"
  }

  # Private Link
  control_plane_private_link = {
    outbound = true
  }
}
```

### Minimal Development

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"

  registry_type = "dockerhub"
  docker_credentials = {
    key_vault_name  = "portkey-dev-kv"
    key_vault_rg    = "portkey-dev-rg"
    username_secret = "docker-username"
    password_secret = "docker-password"
  }

  secrets_key_vault = {
    name           = "portkey-dev-kv"
    resource_group = "portkey-dev-rg"
  }

  environment_variables = {
    gateway = {
      LOG_LEVEL             = "debug"
      NODE_ENV              = "development"
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

  # No VNET, public ingress, built-in Redis
  network_mode   = "none"
  ingress_type   = "aca"
  public_ingress = true

  redis_config = {
    redis_type = "redis"
  }
}
```

---

## Configuration Guides

### Private Link to Control Plane

When using outbound Private Link (`control_plane_private_link.outbound = true`), you must configure the Gateway to use the private Control Plane endpoint.

**Add Control Plane Private Endpoint URLs to environment variables:**

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"

  # Enable Private Link
  control_plane_private_link = {
    outbound = true
  }

  # Configure Gateway to use private endpoint
  environment_variables = {
    gateway = {
      LOG_LEVEL                 = "info"
      NODE_ENV                  = "development"
      ANALYTICS_STORE           = "control_plane"
      AZURE_MANAGED_VERSION     = "2019-08-01"
      ALBUS_BASEPATH            = "https://azure-cp.privatelink-az.portkey.ai/albus"
      CONTROL_PLANE_BASEPATH    = "https://azure-cp.privatelink-az.portkey.ai/api/v1"
      SOURCE_SYNC_API_BASEPATH  = "https://azure-cp.privatelink-az.portkey.ai/api/v1/sync"
      CONFIG_READER_PATH        = "https://azure-cp.privatelink-az.portkey.ai/api/model-configs"
    }
  }

  # ... rest of configuration
}
```

**What gets created:**
- Private Endpoint in your VNET
- Private DNS Zone (`privatelink-az.portkey.ai`) with A record (`azure-cp`)
- VNET link for DNS resolution

**Post-deployment:**

The Private Endpoint connection requires manual approval from Portkey. Contact them with:

```bash
terraform output control_plane_private_endpoint_id
```

**Verify:**

```bash
# Check PE approval status
az network private-endpoint show \
  --ids $(terraform output -raw control_plane_private_endpoint_id) \
  --query 'privateLinkServiceConnections[0].privateLinkServiceConnectionState.status'

# Check Gateway logs for Control Plane connectivity
az containerapp logs show -n gateway -g <resource-group> --follow
```
---

## Multi-Environment Setup

Manage dev, staging, and prod from one codebase:

```
my-infrastructure/
├── dev/
│   ├── main.tf
│   ├── backend.config
│   └── terraform.tfvars
├── staging/
│   ├── main.tf
│   ├── backend.config
│   └── terraform.tfvars
└── prod/
    ├── main.tf
    ├── backend.config
    └── terraform.tfvars
```

**Shared `main.tf` (identical in each environment):**

```hcl
terraform {
  required_version = ">= 1.5"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"

  environment = var.environment
  
  # ... use variables for environment-specific values
}
```

**Environment-specific `backend.config`:**

```hcl
# dev/backend.config
key = "portkey-gateway/dev.tfstate"

# staging/backend.config
key = "portkey-gateway/staging.tfstate"

# prod/backend.config
key = "portkey-gateway/prod.tfstate"
```

**Environment-specific `terraform.tfvars`:**

```hcl
# dev/terraform.tfvars
environment = "dev"
capacity    = 1

# prod/terraform.tfvars
environment = "prod"
capacity    = 3
```

**Deploy each environment:**

```bash
# Dev
cd dev
terraform init -backend-config=backend.config
terraform apply

# Prod
cd ../prod
terraform init -backend-config=backend.config
terraform apply
```

## Version Pinning

Always pin to a specific version in production:

```hcl
# Good - pinned to v1.0.0
source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"

# Bad - uses latest from main branch
source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca"

# OK for development only
source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=main"
```

## Upgrading

### 1. Check Release Notes

Visit https://github.com/Portkey-AI/portkey-gateway-infrastructure/releases

Review:
- New features
- Breaking changes
- Bug fixes
- Required variable changes

### 2. Test in Non-Prod

Update `dev/main.tf`:

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.1.0"
  # ...
}
```

```bash
cd dev
terraform init -upgrade
terraform plan
terraform apply
```

Verify the deployment works as expected.

### 3. Promote to Production

After successful testing, update `prod/main.tf`:

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.1.0"
  # ...
}
```

```bash
cd prod
terraform init -upgrade
terraform plan  # Review changes carefully
terraform apply
```

### Rollback

If issues occur, revert to the previous version:

```hcl
source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"
```

```bash
terraform init -upgrade
terraform apply
```

---

## Next Steps

- **Configuration Details**: See [Variables.md](Variables.md) for all available options
- **Main README**: For configuration guides (Redis, Private Link, App Gateway, etc.)
