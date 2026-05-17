# External Redis Configuration

Guide for using an existing Amazon ElastiCache for Redis OSS or Valkey cluster instead of the built-in Redis container.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Clone & Deploy Configuration](#clone--deploy-configuration)
- [Module-Based Configuration](#module-based-configuration)
- [Environment Variables Set by Terraform](#environment-variables-set-by-terraform)

---

## Prerequisites

You should already have an ElastiCache cluster provisioned. Gather the following before configuring Terraform:

| Item | Notes |
|------|--------|
| **Endpoint** | Primary endpoint (standalone) or Configuration endpoint ([cluster mode](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Endpoints.html)) — e.g. `master.portkey-redis.xxxxx.use1.cache.amazonaws.com:6379` |
| **TLS** | Set `tls = true` in `redis_configuration` if transit encryption is enabled on the cluster |
| **Mode** | `standalone` or `cluster` (cluster mode enabled) |
| **Network** | ElastiCache's security groups must allow **inbound TCP 6379** (or your port) from gateway and data-service task security groups |
| **AUTH token** (optional) | If ElastiCache AUTH is enabled, store the token in **AWS Secrets Manager** as JSON with a `REDIS_PASSWORD` key and reference the secret **ARN** in `secrets` / `secrets.json`. Omit `REDIS_PASSWORD` if AUTH is disabled |

When `redis_configuration.redis_type = "aws-elastic-cache"`, the built-in Redis ECS service is **not** deployed.

---

## Clone & Deploy Configuration

### 1. Update `dev.tfvars`

```hcl
redis_configuration = {
  redis_type = "aws-elastic-cache"
  cpu        = 256   # Ignored for ElastiCache
  memory     = 512   # Ignored for ElastiCache
  endpoint   = "master.portkey-redis.xxxxx.use1.cache.amazonaws.com:6379"
  tls        = true  # Match your cluster's transit encryption setting
  mode       = "standalone"  # or "cluster"
}
```

| Field | Description |
|-------|-------------|
| `redis_type` | Must be `aws-elastic-cache` |
| `endpoint` | Your ElastiCache primary or configuration endpoint |
| `tls` | `true` when transit encryption is enabled |
| `mode` | `standalone` or `cluster` |

### 2. Add Password to `secrets.json` (if AUTH enabled)

**`environments/dev/secrets.json`:**

```json
{
  "gateway": {
    "PORTKEY_CLIENT_AUTH": "<ClientOrgSecretNameArn>",
    "ORGANISATIONS_TO_SYNC": "<ClientOrgSecretNameArn>",
    "REDIS_PASSWORD": "<RedisAuthSecretArn>"
  },
  "data-service": {
    "PORTKEY_CLIENT_AUTH": "<ClientOrgSecretNameArn>",
    "ORGANISATIONS_TO_SYNC": "<ClientOrgSecretNameArn>",
    "REDIS_PASSWORD": "<RedisAuthSecretArn>"
  }
}
```

> **Important:** `<RedisAuthSecretArn>` is the Secrets Manager **ARN**. The secret value must be JSON containing a `REDIS_PASSWORD` key.

### 3. Deploy

```bash
terraform init -backend-config=environments/dev/backend.config
terraform apply -var-file=environments/dev/dev.tfvars
```

---

## Module-Based Configuration

### Option 1: Using `secrets` Variable

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  redis_configuration = {
    redis_type = "aws-elastic-cache"
    cpu        = 256
    memory     = 512
    endpoint   = "master.portkey-redis.xxxxx.use1.cache.amazonaws.com:6379"
    tls        = true
    mode       = "standalone"
  }

  secrets = {
    gateway = {
      PORTKEY_CLIENT_AUTH   = "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/dev/client-org"
      ORGANISATIONS_TO_SYNC = "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/dev/client-org"
      REDIS_PASSWORD        = "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/dev/redis-auth"
    }
  }

  # ... other config
}
```

### Option 2: Using JSON Files

**`config/secrets.json`:**

```json
{
  "gateway": {
    "PORTKEY_CLIENT_AUTH": "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/dev/client-org",
    "ORGANISATIONS_TO_SYNC": "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/dev/client-org",
    "REDIS_PASSWORD": "arn:aws:secretsmanager:us-east-1:123456789012:secret:portkey-gateway/dev/redis-auth"
  }
}
```

**`main.tf`:**

```hcl
module "portkey_gateway" {
  source = "github.com/Portkey-AI/portkey-gateway-infrastructure//terraform/ecs?ref=v1.0.0"

  redis_configuration = {
    redis_type = "aws-elastic-cache"
    endpoint   = "master.portkey-redis.xxxxx.use1.cache.amazonaws.com:6379"
    tls        = true
    mode       = "standalone"
    cpu        = 256
    memory     = 512
  }

  environment_variables = jsondecode(file("${path.root}/config/environment-variables.json"))
  secrets               = jsondecode(file("${path.root}/config/secrets.json"))

  # ... other config
}
```

---
