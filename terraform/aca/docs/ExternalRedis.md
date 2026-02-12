# External Redis Configuration

Guide for using Azure Cache for Redis instead of the built-in Redis container.

## Table of Contents

- [Create Azure Managed Redis](#create-azure-managed-redis)
- [Store Password in Key Vault](#store-password-in-key-vault)
- [Clone & Deploy Configuration](#clone--deploy-configuration)
- [Module-Based Configuration](#module-based-configuration)
- [Private Endpoint Setup](#private-endpoint-setup)


---

## Create Azure Managed Redis

```bash
# Set variables
rg="portkey-rg"
redis_name="portkey-redis-$(date +%s)"  # Add timestamp for uniqueness
location="eastus"

# Create Redis (Basic tier for development)
# Note: Redis names must be globally unique across Azure
az redis create \
  --name ${redis_name} \
  --resource-group ${rg} \
  --location ${location} \
  --sku Basic \
  --vm-size c0

# Get connection details
redis_host=$(az redis show --name ${redis_name} --resource-group ${rg} --query hostName -o tsv)
echo "Endpoint: rediss://${redis_host}:6380"
```

---

## Store Password in Key Vault

```bash
# Get Redis password
redis_password=$(az redis list-keys \
  --name ${redis_name} \
  --resource-group ${rg} \
  --query primaryKey -o tsv)

# Store in Key Vault
kv="portkey-kv"
az keyvault secret set \
  --vault-name ${kv} \
  --name redis-password \
  --value "${redis_password}"
```

---

## Clone & Deploy Configuration

### 1. Update `terraform.tfvars`

```hcl
redis_config = {
  redis_type = "azure-managed-redis"
  endpoint   = "rediss://portkey-redis.redis.cache.windows.net:6380"
  tls        = true
  mode       = "standalone"  # or "cluster" for clustered redis
}

secrets_key_vault = {
  name           = "portkey-kv"
  resource_group = "portkey-rg"
}

secrets_file_path = "environments/dev/secrets.json"
```

### 2. Add Password to `secrets.json`

**`environments/dev/secrets.json`:**

```json
{
  "gateway": {
    "PORTKEY_CLIENT_AUTH": "portkey-client-auth",
    "ORGANISATIONS_TO_SYNC": "organisations-to-sync",
    "REDIS_PASSWORD": "redis-password"
  }
}
```

> **Important:** `"redis-password"` is the Key Vault secret **name**, not the actual password value.

### 3. Deploy

```bash
terraform init -backend-config=backend.config
terraform apply -var-file=environments/dev/dev.tfvars
```

---

## Module-Based Configuration

### Option 1: Using `secrets` Variable

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"

  project_name = "portkey-gateway"
  environment  = "dev"

  redis_config = {
    redis_type = "azure-managed-redis"
    endpoint   = "rediss://portkey-redis.redis.cache.windows.net:6380"
    tls        = true
    mode       = "standalone"
  }

  secrets_key_vault = {
    name           = "portkey-kv"
    resource_group = "portkey-rg"
  }

  secrets = {
    gateway = {
      PORTKEY_CLIENT_AUTH    = "portkey-client-auth"
      ORGANISATIONS_TO_SYNC  = "organisations-to-sync"
      REDIS_PASSWORD         = "redis-password"                       # Key Vault secret name
    }
  }

  # Other config...
  registry_type = "dockerhub"
  docker_credentials = {
    key_vault_name  = "portkey-kv"
    key_vault_rg    = "portkey-rg"
    username_secret = "docker-username"
    password_secret = "docker-password"
  }

  environment_variables = {
    gateway = {
      LOG_LEVEL = "info"
      NODE_ENV  = "development"
    }
  }
}
```

### Option 2: Using JSON Files

**`config/secrets.json`:**
```json
{
  "gateway": {
    "PORTKEY_CLIENT_AUTH": "portkey-client-auth",
    "ORGANISATIONS_TO_SYNC": "organisations-to-sync",
    "REDIS_PASSWORD": "redis-password"
  }
}
```

**`main.tf`:**
```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/aca?ref=v1.0.0"

  redis_config = {
    redis_type = "azure-managed-redis"
    endpoint   = "rediss://portkey-redis.redis.cache.windows.net:6380"
    tls        = true
    mode       = "standalone"
  }

  secrets = jsondecode(file("${path.root}/config/secrets.json"))
  
  # ... other config
}
```

---

## Private Endpoint Setup

For VNET-integrated deployments, use Private Endpoint for private connectivity to Redis.

**Prerequisites:**
- `network_mode = "new"` or `"existing"`
- Premium tier Redis (or Standard/Basic with Private Endpoint support)

```bash
# Create Private Endpoint
az network private-endpoint create \
  --name pe-redis \
  --resource-group portkey-rg \
  --vnet-name vnet-portkey-gateway \
  --subnet snet-pe \
  --private-connection-resource-id $(az redis show --name portkey-redis --resource-group portkey-rg --query id -o tsv) \
  --group-id redisCache \
  --connection-name redis-connection

# Get Private Endpoint IP
pe_ip=$(az network private-endpoint show --name pe-redis --resource-group portkey-rg --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv)

# Create Private DNS Zone
az network private-dns zone create \
  --name privatelink.redis.cache.windows.net \
  --resource-group portkey-rg

# Link to VNET
az network private-dns link vnet create \
  --name redis-dns-link \
  --resource-group portkey-rg \
  --zone-name privatelink.redis.cache.windows.net \
  --virtual-network vnet-portkey-gateway \
  --registration-enabled false

# Add A record
az network private-dns record-set a add-record \
  --record-set-name portkey-redis \
  --resource-group portkey-rg \
  --zone-name privatelink.redis.cache.windows.net \
  --ipv4-address ${pe_ip}
```

**Update endpoint in tfvars:**

```hcl
redis_config = {
  redis_type = "azure-managed-redis"
  endpoint   = "rediss://portkey-redis.privatelink.redis.cache.windows.net:6380"  # Private DNS
  tls        = true
  mode       = "standalone"
}
```

---
